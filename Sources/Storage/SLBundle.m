#import "SLBundle.h"
#import "SLJSON.h"
#import "SLBytes.h"
#import "SLError.h"
NSData *SLBundleEncode(NSArray *fixtures) {
    SLRequire(fixtures.count <= 10000, @"bundle.limit", @"Too many fixtures in bundle");
    NSMutableArray *entries = [NSMutableArray array];
    NSUInteger total = 0;
    for (SLFixture *fixture in fixtures) {
        NSData *data = SLJSONData(fixture.document);
        total += data.length;
        SLRequire(total <= 24 * 1024 * 1024, @"bundle.limit",
                  @"Bundle payload exceeds 24 MiB; export one fixture at a time");
        [entries addObject:@{@"sha256" : SLSHA256(data), @"fixture" : fixture.document}];
    }
    NSDictionary *payload = @{@"fixtures" : entries};
    return SLJSONData(@{
        @"format" : @"sluice.bundle",
        @"version" : @1,
        @"payload" : payload,
        @"sha256" : SLSHA256(SLJSONData(payload))
    });
}
NSArray *SLBundleDecode(NSData *data) {
    NSDictionary *root = SLObject(SLJSONRead(data), @"bundle");
    SLKeys(root, @[ @"format", @"version", @"payload", @"sha256" ],
           @[ @"format", @"version", @"payload", @"sha256" ], @"bundle");
    SLRequire([root[@"format"] isEqual:@"sluice.bundle"], @"bundle.format",
              @"Not a Sluice fixture bundle");
    SLInteger(root[@"version"], 1, 1, @"bundle.version");
    NSDictionary *payload = SLObject(root[@"payload"], @"payload");
    SLKeys(payload, @[ @"fixtures" ], @[ @"fixtures" ], @"payload");
    SLRequire([SLSHA256(SLJSONData(payload)) isEqual:SLString(root[@"sha256"], 64, @"sha256")],
              @"bundle.checksum", @"Bundle payload checksum mismatch");
    NSMutableArray *fixtures = [NSMutableArray array];
    NSMutableSet *ids = [NSMutableSet set];
    for (id item in SLArray(payload[@"fixtures"], 10000, @"fixtures")) {
        NSDictionary *entry = SLObject(item, @"entry");
        SLKeys(entry, @[ @"sha256", @"fixture" ], @[ @"sha256", @"fixture" ], @"entry");
        SLRequire([SLSHA256(SLJSONData(entry[@"fixture"]))
                      isEqual:SLString(entry[@"sha256"], 64, @"entry.sha256")],
                  @"bundle.checksum", @"Fixture checksum mismatch");
        SLFixture *fixture = [[SLFixture alloc] initWithDocument:entry[@"fixture"]];
        SLRequire(![ids containsObject:fixture.identifier], @"bundle.duplicate",
                  @"Duplicate fixture id in bundle");
        [ids addObject:fixture.identifier];
        [fixtures addObject:fixture];
    }
    return [fixtures copy];
}
