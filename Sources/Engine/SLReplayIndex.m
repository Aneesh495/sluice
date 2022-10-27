#import "SLReplayIndex.h"
#import "SLBytes.h"
#import "SLJSON.h"
#import "SLError.h"
@implementation SLReplayIndex {
    NSDictionary<NSString *, NSArray<SLFixture *> *> *_index;
    NSString *_privacy;
}
- (instancetype)initWithFixtures:(NSArray *)fixtures privacy:(SLPrivacy *)privacy {
    if ((self = [super init])) {
        NSMutableDictionary *index = [NSMutableDictionary dictionary];
        for (SLFixture *fixture in fixtures) {
            if (!index[fixture.identity])
                index[fixture.identity] = [NSMutableArray array];
            [index[fixture.identity] addObject:fixture];
        }
        NSMutableDictionary *frozen = [NSMutableDictionary dictionary];
        for (NSString *key in index)
            frozen[key] = [index[key] copy];
        _index = [frozen copy];
        _privacy = privacy.digest;
    }
    return self;
}
- (SLFixture *)select:(NSString *)identity identifier:(NSString *)identifier {
    NSArray *matches = _index[identity] ?: @[];
    SLFixture *selected = nil;
    NSString *responseDigest = nil;
    for (SLFixture *fixture in matches) {
        if (identifier && ![fixture.identifier isEqual:identifier])
            continue;
        NSString *digest = SLSHA256(SLJSONData(fixture.document[@"response"]));
        SLRequire(!responseDigest || [responseDigest isEqual:digest], @"replay.ambiguous",
                  @"Different responses match this request; select a fixture id");
        responseDigest = digest;
        if (!selected)
            selected = fixture;
    }
    SLRequire(selected != nil, @"replay.miss", @"No recorded fixture matches this request");
    SLRequire([selected.document[@"privacy"] isEqual:_privacy], @"replay.privacy",
              @"Replay requires the privacy policy used to record this fixture");
    SLRequire(selected.replayable, @"replay.body",
              @"Fixture contains an omitted body; capture with a JSON policy to replay it");
    for (NSString *line in [selected.response.headers values:@"Vary"]) {
        for (NSString *field in [line componentsSeparatedByString:@","]) {
            NSString *name =
                [[field stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]
                    lowercaseString];
            SLRequire([@[ @"accept", @"content-type" ] containsObject:name], @"replay.vary",
                      @"Fixture varies on an unrecorded identity field");
        }
    }
    return selected;
}
@end
