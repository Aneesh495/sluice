#import "SLTape.h"
#import "SLReceipt.h"
#import "SLJSON.h"
#import "SLBytes.h"
#import "SLError.h"
@implementation SLTape {
    NSDictionary<NSString *, NSArray<NSString *> *> *_streams;
    BOOL _repeatLast;
}
- (instancetype)initWithDocument:(NSDictionary *)document {
    if ((self = [super init])) {
        document = SLObject(SLJSONRead(SLJSONData(document)), @"tape");
        SLKeys(document, @[ @"version", @"name", @"repeatLast", @"streams" ],
               @[ @"version", @"name", @"repeatLast", @"streams" ], @"tape");
        SLInteger(document[@"version"], 1, 1, @"tape.version");
        SLRequire(SLString(document[@"name"], 256, @"tape.name").length > 0, @"tape.name",
                  @"Tape name cannot be empty");
        SLRequire([document[@"repeatLast"] isKindOfClass:NSNumber.class] &&
                      CFGetTypeID((__bridge CFTypeRef)document[@"repeatLast"]) ==
                          CFBooleanGetTypeID(),
                  @"schema.type", @"repeatLast must be boolean");
        _repeatLast = [document[@"repeatLast"] boolValue];
        NSMutableDictionary *streams = [NSMutableDictionary dictionary];
        NSUInteger references = 0;
        for (id item in SLArray(document[@"streams"], 10000, @"streams")) {
            NSDictionary *stream = SLObject(item, @"stream");
            SLKeys(stream, @[ @"identity", @"fixtures" ], @[ @"identity", @"fixtures" ], @"stream");
            NSString *identity = SLString(stream[@"identity"], 64, @"stream.identity");
            SLRequire(identity.length == 64 &&
                          [identity rangeOfCharacterFromSet:
                                        [NSCharacterSet
                                            characterSetWithCharactersInString:@"0123456789abcdef"]
                                            .invertedSet]
                                  .location == NSNotFound,
                      @"tape.identity", @"Stream identity must be a SHA-256 digest");
            SLRequire(!streams[identity], @"tape.duplicate", @"Tape repeats a request identity");
            NSArray *ids = SLArray(stream[@"fixtures"], 100000, @"stream.fixtures");
            references += ids.count;
            SLRequire(ids.count > 0 && references <= 100000, @"tape.limit",
                      @"Tape must contain nonempty streams within 100000 references");
            for (id identifier in ids)
                SLRequire([[NSUUID alloc]
                              initWithUUIDString:SLString(identifier, 64, @"fixture id")] != nil,
                          @"tape.fixture", @"Invalid fixture UUID in tape");
            streams[identity] = ids;
        }
        SLRequire(streams.count > 0, @"tape.empty", @"Tape must contain at least one stream");
        _streams = [streams copy];
        _document = document;
        _digest = SLSHA256(SLJSONData(document));
    }
    return self;
}
+ (instancetype)fromReceipts:(NSArray *)receipts
                     session:(NSString *)session
                  repeatLast:(BOOL)repeatLast {
    NSMutableDictionary *groups = [NSMutableDictionary dictionary];
    for (NSDictionary *receipt in receipts) {
        SLValidateReceipt(receipt);
        if (![receipt[@"session"] isEqual:session] || ![receipt[@"mode"] isEqual:@"record"])
            continue;
        SLRequire([receipt[@"identity"] length] == 64 && receipt[@"fixture"] != nil,
                  @"tape.incomplete", @"Recording has an exchange without a complete fixture");
        NSString *identity = receipt[@"identity"];
        if (!groups[identity])
            groups[identity] = [NSMutableArray array];
        [groups[identity] addObject:receipt];
    }
    NSMutableArray *streams = [NSMutableArray array];
    for (NSString *identity in [[groups allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        NSArray *sorted = [groups[identity]
            sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                return [a[@"occurrence"] compare:b[@"occurrence"]];
            }];
        NSMutableArray *ids = [NSMutableArray array];
        for (NSUInteger i = 0; i < sorted.count; i++) {
            SLRequire([sorted[i][@"occurrence"] unsignedLongLongValue] == i + 1, @"tape.incomplete",
                      @"Recording occurrence sequence has a gap or duplicate");
            [ids addObject:sorted[i][@"fixture"]];
        }
        [streams addObject:@{@"identity" : identity, @"fixtures" : ids}];
    }
    return [[self alloc] initWithDocument:@{
        @"version" : @1,
        @"name" : [@"recording-" stringByAppendingString:session],
        @"repeatLast" : @(repeatLast),
        @"streams" : streams
    }];
}
- (NSString *)fixtureForIdentity:(NSString *)identity occurrence:(uint64_t)occurrence {
    NSArray *ids = _streams[identity];
    SLRequire(occurrence > 0 && ids.count > 0, @"tape.miss",
              @"No tape stream matches this request identity");
    if (occurrence > ids.count) {
        SLRequire(_repeatLast, @"tape.exhausted", @"Recorded response sequence is exhausted");
        return ids.lastObject;
    }
    return ids[(NSUInteger)occurrence - 1];
}
- (void)validateFixtures:(NSArray *)fixtures {
    NSMutableDictionary *byID = [NSMutableDictionary dictionary];
    for (SLFixture *fixture in fixtures)
        byID[fixture.identifier] = fixture;
    for (NSString *identity in _streams)
        for (NSString *identifier in _streams[identity]) {
            SLFixture *fixture = byID[identifier];
            SLRequire(fixture != nil && [fixture.identity isEqual:identity] && fixture.replayable,
                      @"tape.fixture",
                      @"Tape references a missing mismatched or unreplayable fixture");
        }
}
@end
