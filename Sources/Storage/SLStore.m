#import "SLStore.h"
#import "SLJSON.h"
#import "SLBytes.h"
#import "SLError.h"
#import "SLReceipt.h"
#import <sqlite3.h>
#import <sys/stat.h>

@implementation SLStore {
    sqlite3 *_db;
}
- (void)sql:(const char *)sql {
    int rc = sqlite3_exec(_db, sql, NULL, NULL, NULL);
    SLRequire(rc == SQLITE_OK, @"store.sql", @"SQLite statement failed");
}
- (sqlite3_stmt *)prepare:(const char *)sql {
    sqlite3_stmt *statement = NULL;
    SLRequire(sqlite3_prepare_v2(_db, sql, -1, &statement, NULL) == SQLITE_OK, @"store.prepare",
              @"Cannot prepare SQLite statement");
    return statement;
}
- (instancetype)initWithDirectory:(NSString *)directory {
    if ((self = [super init])) {
        _directory = [directory.stringByStandardizingPath copy];
        NSFileManager *fm = NSFileManager.defaultManager;
        NSError *error = nil;
        SLRequire([fm createDirectoryAtPath:_directory
                      withIntermediateDirectories:YES
                                       attributes:@{NSFilePosixPermissions : @0700}
                                            error:&error],
                  @"store.directory", @"Cannot create workspace directory");
        struct stat st;
        SLRequire(lstat(_directory.fileSystemRepresentation, &st) == 0 && S_ISDIR(st.st_mode) &&
                      st.st_uid == getuid(),
                  @"store.directory", @"Workspace must be an owned directory, not a symlink");
        SLRequire(chmod(_directory.fileSystemRepresentation, 0700) == 0, @"store.permissions",
                  @"Cannot restrict workspace permissions");
        NSString *path = [_directory stringByAppendingPathComponent:@"store.sqlite3"];
        int rc = sqlite3_open_v2(path.fileSystemRepresentation, &_db,
                                 SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE |
                                     SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_NOFOLLOW,
                                 NULL);
        SLRequire(rc == SQLITE_OK, @"store.open", @"Cannot open SQLite workspace");
        chmod(path.fileSystemRepresentation, 0600);
        sqlite3_busy_timeout(_db, 2000);
        [self sql:"PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA foreign_keys=ON; "
                  "PRAGMA trusted_schema=OFF; PRAGMA max_page_count=262144;"];
        sqlite3_stmt *version = [self prepare:"PRAGMA user_version"];
        int schema = 0;
        if (sqlite3_step(version) == SQLITE_ROW)
            schema = sqlite3_column_int(version, 0);
        sqlite3_finalize(version);
        SLRequire(schema <= 1, @"store.version",
                  @"Workspace was created by a newer Sluice version");
        [self sql:"BEGIN IMMEDIATE; CREATE TABLE IF NOT EXISTS fixtures(id TEXT PRIMARY KEY, "
                  "identity TEXT NOT NULL, digest TEXT NOT NULL UNIQUE, payload BLOB NOT NULL, "
                  "hash TEXT NOT NULL, created INTEGER NOT NULL); CREATE INDEX IF NOT EXISTS "
                  "fixtures_identity ON fixtures(identity); CREATE TABLE IF NOT EXISTS receipts(id "
                  "TEXT PRIMARY KEY, payload BLOB NOT NULL, hash TEXT NOT NULL, created INTEGER "
                  "NOT NULL); PRAGMA user_version=1; COMMIT;"];
    }
    return self;
}
- (void)dealloc {
    if (_db)
        sqlite3_close_v2(_db);
}
- (NSUInteger)count:(const char *)sql {
    sqlite3_stmt *s = [self prepare:sql];
    NSUInteger result = 0;
    @try {
        SLRequire(sqlite3_step(s) == SQLITE_ROW, @"store.read", @"Cannot read workspace count");
        result = (NSUInteger)sqlite3_column_int64(s, 0);
    } @finally {
        sqlite3_finalize(s);
    }
    return result;
}
static void Bind(sqlite3_stmt *s, int index, NSString *text) {
    SLRequire(sqlite3_bind_text(s, index, text.UTF8String, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              @"store.bind", @"Cannot bind SQLite text");
}
- (NSString *)insertFixture:(SLFixture *)fixture {
    sqlite3_stmt *existing = [self prepare:"SELECT id FROM fixtures WHERE digest=?"];
    @try {
        Bind(existing, 1, fixture.digest);
        int rc = sqlite3_step(existing);
        if (rc == SQLITE_ROW)
            return @((const char *)sqlite3_column_text(existing, 0));
        SLRequire(rc == SQLITE_DONE, @"store.read", @"Cannot inspect fixture content identity");
    } @finally {
        sqlite3_finalize(existing);
    }
    SLRequire([self count:"SELECT count(*) FROM fixtures"] < 10000, @"store.quota",
              @"Workspace fixture limit reached");
    NSData *data = SLJSONData(fixture.document);
    sqlite3_stmt *s = [self
        prepare:
            "INSERT INTO fixtures(id,identity,digest,payload,hash,created) VALUES(?,?,?,?,?,?)"];
    @try {
        Bind(s, 1, fixture.identifier);
        Bind(s, 2, fixture.identity);
        Bind(s, 3, fixture.digest);
        sqlite3_bind_blob(s, 4, data.bytes, (int)data.length, SQLITE_TRANSIENT);
        Bind(s, 5, SLSHA256(data));
        sqlite3_bind_int64(s, 6, [fixture.document[@"createdMs"] longLongValue]);
        SLRequire(sqlite3_step(s) == SQLITE_DONE, @"store.write", @"Cannot insert fixture");
    } @finally {
        sqlite3_finalize(s);
    }
    return fixture.identifier;
}
- (NSString *)saveFixture:(SLFixture *)fixture {
    @synchronized(self) {
        [self sql:"BEGIN IMMEDIATE"];
        @try {
            NSString *identifier = [self insertFixture:fixture];
            [self sql:"COMMIT"];
            return identifier;
        } @catch (NSException *e) {
            [self sql:"ROLLBACK"];
            @throw;
        }
    }
}
- (NSArray *)queryFixtures:(NSString *)value field:(NSString *)field {
    const char *sql =
        [field isEqual:@"id"]
            ? "SELECT payload,hash,id,identity,digest FROM fixtures WHERE id=? ORDER BY created,id"
        : [field isEqual:@"identity"]
            ? "SELECT payload,hash,id,identity,digest FROM fixtures WHERE identity=? ORDER BY "
              "created,id"
            : "SELECT payload,hash,id,identity,digest FROM fixtures ORDER BY created,id";
    sqlite3_stmt *s = [self prepare:sql];
    NSMutableArray *result = [NSMutableArray array];
    @try {
        if (value)
            Bind(s, 1, value);
        int rc;
        while ((rc = sqlite3_step(s)) == SQLITE_ROW) {
            NSData *data = [NSData dataWithBytes:sqlite3_column_blob(s, 0)
                                          length:(NSUInteger)sqlite3_column_bytes(s, 0)];
            NSString *hash = @((const char *)sqlite3_column_text(s, 1));
            SLRequire([SLSHA256(data) isEqual:hash], @"store.corrupt",
                      @"Fixture payload hash mismatch");
            SLFixture *fixture = [[SLFixture alloc] initWithDocument:SLJSONRead(data)];
            SLRequire([fixture.identifier isEqual:@((const char *)sqlite3_column_text(s, 2))] &&
                          [fixture.identity isEqual:@((const char *)sqlite3_column_text(s, 3))] &&
                          [fixture.digest isEqual:@((const char *)sqlite3_column_text(s, 4))],
                      @"store.corrupt",
                      @"Fixture lookup metadata disagrees with validated payload");
            [result addObject:fixture];
        }
        SLRequire(rc == SQLITE_DONE, @"store.read", @"Cannot enumerate fixtures");
    } @finally {
        sqlite3_finalize(s);
    }
    return result;
}
- (NSArray *)fixtures {
    @synchronized(self) {
        return [self queryFixtures:nil field:@"all"];
    }
}
- (SLFixture *)fixture:(NSString *)identifier {
    @synchronized(self) {
        return [self queryFixtures:identifier field:@"id"].firstObject;
    }
}
- (NSArray *)matching:(NSString *)identity {
    @synchronized(self) {
        return [self queryFixtures:identity field:@"identity"];
    }
}
- (void)saveReceipt:(NSDictionary *)receipt {
    @synchronized(self) {
        SLValidateReceipt(receipt);
        NSString *identifier = SLString(receipt[@"id"], 64, @"receipt.id");
        SLInteger(receipt[@"createdMs"], 0, INT64_MAX, @"receipt.createdMs");
        NSData *data = SLJSONData(receipt);
        SLRequire(data.length <= 65536, @"receipt.limit", @"Receipt exceeds 64 KiB");
        [self sql:"BEGIN IMMEDIATE"];
        @try {
            SLRequire([self count:"SELECT count(*) FROM receipts"] < 100000, @"store.quota",
                      @"Workspace receipt limit reached");
            sqlite3_stmt *s =
                [self prepare:"INSERT INTO receipts(id,payload,hash,created) VALUES(?,?,?,?)"];
            @try {
                Bind(s, 1, identifier);
                sqlite3_bind_blob(s, 2, data.bytes, (int)data.length, SQLITE_TRANSIENT);
                Bind(s, 3, SLSHA256(data));
                sqlite3_bind_int64(s, 4, [receipt[@"createdMs"] longLongValue]);
                SLRequire(sqlite3_step(s) == SQLITE_DONE, @"store.write", @"Cannot insert receipt");
            } @finally {
                sqlite3_finalize(s);
            }
            [self sql:"COMMIT"];
        } @catch (NSException *e) {
            [self sql:"ROLLBACK"];
            @throw;
        }
    }
}
- (NSArray *)receipts:(NSUInteger)limit {
    @synchronized(self) {
        SLRequire(limit > 0 && limit <= 100000, @"store.limit",
                  @"Receipt limit must be 1 through 100000");
        sqlite3_stmt *s = [self
            prepare:"SELECT payload,hash FROM receipts ORDER BY created DESC,id DESC LIMIT ?"];
        sqlite3_bind_int64(s, 1, (sqlite3_int64)limit);
        NSMutableArray *result = [NSMutableArray array];
        @try {
            int rc;
            while ((rc = sqlite3_step(s)) == SQLITE_ROW) {
                NSData *data = [NSData dataWithBytes:sqlite3_column_blob(s, 0)
                                              length:(NSUInteger)sqlite3_column_bytes(s, 0)];
                SLRequire([SLSHA256(data) isEqual:@((const char *)sqlite3_column_text(s, 1))],
                          @"store.corrupt", @"Receipt payload hash mismatch");
                NSDictionary *receipt = SLJSONRead(data);
                SLValidateReceipt(receipt);
                [result addObject:receipt];
            }
            SLRequire(rc == SQLITE_DONE, @"store.read", @"Cannot enumerate receipts");
        } @finally {
            sqlite3_finalize(s);
        }
        return result;
    }
}
- (NSDictionary *)statistics {
    @synchronized(self) {
        return @{
            @"fixtures" : @([self count:"SELECT count(*) FROM fixtures"]),
            @"receipts" : @([self count:"SELECT count(*) FROM receipts"]),
            @"schema" : @1
        };
    }
}
- (void)importFixtures:(NSArray *)fixtures {
    @synchronized(self) {
        [self sql:"BEGIN IMMEDIATE"];
        @try {
            for (SLFixture *fixture in fixtures)
                [self insertFixture:fixture];
            [self sql:"COMMIT"];
        } @catch (NSException *e) {
            [self sql:"ROLLBACK"];
            @throw;
        }
    }
}
- (void)checkIntegrity {
    @synchronized(self) {
        sqlite3_stmt *s = [self prepare:"PRAGMA integrity_check"];
        @try {
            SLRequire(sqlite3_step(s) == SQLITE_ROW &&
                          !strcmp((const char *)sqlite3_column_text(s, 0), "ok"),
                      @"store.corrupt", @"SQLite integrity check failed");
        } @finally {
            sqlite3_finalize(s);
        }
        (void)[self fixtures];
        (void)[self receipts:100000];
    }
}
@end
