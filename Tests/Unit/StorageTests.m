#import "SLTest.h"
#import "SLStore.h"
#import "SLBundle.h"
#import "SLJSON.h"
#import "SLBytes.h"
#import "SLReceipt.h"
#import <sqlite3.h>
static SLFixture *Fixture(NSString *target, NSString *text) {
    SLMessage *request = [SLMessage new];
    request.request = YES;
    request.target = target;
    SLMessage *response = [SLMessage response:200
                                         body:SLUTF8(text)
                                  contentType:@"application/json"];
    return [SLFixture captureRequest:request
                            response:response
                             privacy:[[SLPrivacy alloc] initWithDocument:@{
                                 @"version" : @1,
                                 @"bodies" : @"json"
                             }]];
}
static void Workspace(void (^body)(SLStore *, NSString *)) {
    NSString *path = [@"build/work" stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    @try {
        body([[SLStore alloc] initWithDirectory:path], path);
    } @finally {
        [NSFileManager.defaultManager removeItemAtPath:path error:NULL];
    }
}
void SLTestStorage(void) {
    SLTest(@"store deduplicates identical captures and survives reopen", ^{
        Workspace(^(SLStore *store, NSString *path) {
            SLFixture *f = Fixture(@"/a", @"{\"id\":1}");
            NSString *a = [store saveFixture:f];
            EQUAL(a, [store saveFixture:Fixture(@"/a", @"{\"id\":1}")]);
            CHECK(store.fixtures.count == 1);
            SLStore *reopened = [[SLStore alloc] initWithDirectory:path];
            EQUAL([reopened fixture:a].digest, f.digest);
            [reopened checkIntegrity];
        });
    });
    SLTest(@"fixture import rolls back every insertion on conflicting id", ^{
        Workspace(^(SLStore *store, NSString *path) {
            SLFixture *a = Fixture(@"/a", @"{}");
            [store saveFixture:a];
            NSMutableDictionary *doc = [Fixture(@"/c", @"{\"n\":2}").document mutableCopy];
            doc[@"id"] = a.identifier;
            SLFixture *conflict = [[SLFixture alloc] initWithDocument:doc];
            SLThrows(@"store.write", ^{
                [store importFixtures:@[ Fixture(@"/b", @"{}"), conflict ]];
            });
            CHECK(store.fixtures.count == 1);
        });
    });
    SLTest(@"bundle validates checksums before mutation", ^{
        SLFixture *f = Fixture(@"/a", @"{\"id\":1}");
        NSData *data = SLBundleEncode(@[ f ]);
        EQUAL(SLBundleDecode(data)[0].document, f.document);
        NSMutableDictionary *root = [SLJSONRead(data) mutableCopy];
        root[@"sha256"] = [@"0" stringByPaddingToLength:64 withString:@"0" startingAtIndex:0];
        SLThrows(@"bundle.checksum", ^{
            SLBundleDecode(SLJSONData(root));
        });
    });
    SLTest(@"store integrity checks detect tampered lookup indexes", ^{
        Workspace(^(SLStore *store, NSString *path) {
            [store saveFixture:Fixture(@"/a", @"{}")];
            sqlite3 *db = NULL;
            CHECK(sqlite3_open([[path stringByAppendingPathComponent:@"store.sqlite3"]
                                   fileSystemRepresentation],
                               &db) == SQLITE_OK);
            CHECK(sqlite3_exec(db, "UPDATE fixtures SET identity='wrong-index'", NULL, NULL,
                               NULL) == SQLITE_OK);
            sqlite3_close(db);
            SLThrows(@"store.corrupt", ^{
                [store checkIntegrity];
            });
        });
    });
}
