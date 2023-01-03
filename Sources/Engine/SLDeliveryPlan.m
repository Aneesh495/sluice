#import "SLDeliveryPlan.h"
#import "SLWire.h"
#import "SLRandom.h"
#import "SLBytes.h"
#import "SLError.h"
#import "SLHead.h"
@implementation SLDeliveryPlan {
    NSUInteger _headBytes;
    NSUInteger _bodyBytes;
    NSUInteger _chunkBytes;
    NSUInteger _rate;
}
- (instancetype)initResponse:(SLMessage *)response
                     request:(SLMessage *)request
                        rule:(SLRule *)rule
                    scenario:(SLScenario *)scenario
                    identity:(NSString *)identity
                  occurrence:(uint64_t)occurrence {
    if ((self = [super init])) {
        SLAction *action = rule ? rule.action : [[SLAction alloc] initWithDocument:@{}];
        _response = [action apply:response];
        uint64_t jitter = rule && action.jitterMS ? SLDraw(scenario.seed, rule.identifier, identity,
                                                           occurrence, @"jitter") %
                                                        (action.jitterMS + 1)
                                                  : 0;
        _delayUS = (action.delayMS + jitter) * 1000;
        BOOL noBody =
            [request.method isEqual:@"HEAD"] || _response.status == 204 || _response.status == 304;
        NSUInteger advertised = _response.body.length;
        if (noBody && _response.status != 204 && !advertised) {
            BOOL present = NO;
            NSUInteger length = SLContentLength(_response.headers, &present);
            if (present)
                advertised = length;
        }
        NSData *body = noBody ? NSData.data : _response.body;
        if (action.truncateAfter)
            body = [body
                subdataWithRange:NSMakeRange(0, MIN(body.length,
                                                    action.truncateAfter.unsignedIntegerValue))];
        NSData *head = SLWireResponseHead(_response, advertised);
        _headBytes = action.disconnect ? 0 : head.length;
        _bodyBytes = action.disconnect ? 0 : body.length;
        _chunkBytes = action.chunkBytes;
        _rate = action.bytesPerSecond;
        NSMutableData *wire = [NSMutableData data];
        if (!action.disconnect) {
            [wire appendData:head];
            [wire appendData:body];
        }
        _wire = [wire copy];
        _segmentCount = _headBytes ? 1 + (_bodyBytes + _chunkBytes - 1) / _chunkBytes : 0;
        _durationUS = _segmentCount ? [self dueUSAt:_segmentCount - 1] : _delayUS;
        SLRequire(_durationUS <= 120000000, @"plan.duration",
                  @"Delivery plan exceeds the 120 second lifetime budget");
        _summary = @{
            @"version" : @1,
            @"identity" : identity,
            @"occurrence" : @(occurrence),
            @"scenario" : scenario.digest,
            @"rule" : rule.identifier ?: @"passthrough",
            @"status" : @(_response.status),
            @"delayUs" : @(_delayUS),
            @"durationUs" : @(_durationUS),
            @"advertisedBodyBytes" : @(advertised),
            @"deliveredBodyBytes" : @(_bodyBytes),
            @"wireBytes" : @(_wire.length),
            @"wireSHA256" : SLSHA256(_wire),
            @"segments" : @(_segmentCount),
            @"chunkBytes" : @(_chunkBytes),
            @"bytesPerSecond" : @(_rate),
            @"disconnect" : @(action.disconnect),
            @"truncated" : @((BOOL)(!noBody && body.length < _response.body.length))
        };
        SLValidatePlanSummary(_summary);
    }
    return self;
}
- (NSRange)rangeAt:(NSUInteger)index {
    SLRequire(index < self.segmentCount, @"plan.index", @"Delivery segment index is out of range");
    if (!index)
        return NSMakeRange(0, _headBytes);
    NSUInteger offset = (index - 1) * _chunkBytes;
    return NSMakeRange(_headBytes + offset, MIN(_chunkBytes, _bodyBytes - offset));
}
- (uint64_t)dueUSAt:(NSUInteger)index {
    SLRequire(index < self.segmentCount, @"plan.index", @"Delivery segment index is out of range");
    uint64_t offset = index ? (index - 1) * _chunkBytes : 0;
    return self.delayUS + (_rate ? (offset * 1000000 + _rate - 1) / _rate : 0);
}
@end

static void DigestField(NSDictionary *summary, NSString *key) {
    NSString *digest = SLString(summary[key], 64, key);
    SLRequire(
        digest.length == 64 &&
            [digest
                rangeOfCharacterFromSet:[NSCharacterSet
                                            characterSetWithCharactersInString:@"0123456789abcdef"]
                                            .invertedSet]
                    .location == NSNotFound,
        @"plan.digest", @"Invalid plan content digest");
}
void SLValidatePlanSummary(NSDictionary *summary) {
    SLObject(summary, @"plan");
    NSArray *fields = @[
        @"version", @"identity", @"occurrence", @"scenario", @"rule", @"status", @"delayUs",
        @"durationUs", @"advertisedBodyBytes", @"deliveredBodyBytes", @"wireBytes", @"wireSHA256",
        @"segments", @"chunkBytes", @"bytesPerSecond", @"disconnect", @"truncated"
    ];
    SLKeys(summary, fields, fields, @"plan");
    SLInteger(summary[@"version"], 1, 1, @"plan.version");
    SLString(summary[@"identity"], 64, @"plan.identity");
    SLString(summary[@"rule"], 128, @"plan.rule");
    SLInteger(summary[@"occurrence"], 1, INT64_MAX, @"plan.occurrence");
    SLInteger(summary[@"status"], 200, 599, @"plan.status");
    int64_t delay = SLInteger(summary[@"delayUs"], 0, 120000000, @"plan.delayUs");
    int64_t duration = SLInteger(summary[@"durationUs"], 0, 120000000, @"plan.durationUs");
    int64_t advertised =
        SLInteger(summary[@"advertisedBodyBytes"], 0, 8 * 1024 * 1024, @"plan.advertisedBodyBytes");
    int64_t delivered =
        SLInteger(summary[@"deliveredBodyBytes"], 0, 8 * 1024 * 1024, @"plan.deliveredBodyBytes");
    int64_t wire = SLInteger(summary[@"wireBytes"], 0, 9 * 1024 * 1024, @"plan.wireBytes");
    int64_t segments = SLInteger(summary[@"segments"], 0, 8 * 1024 * 1024 + 1, @"plan.segments");
    int64_t chunk = SLInteger(summary[@"chunkBytes"], 1, 1048576, @"plan.chunkBytes");
    SLInteger(summary[@"bytesPerSecond"], 0, 1000000000, @"plan.bytesPerSecond");
    SLRequire(SLIsBoolean(summary[@"disconnect"]) && SLIsBoolean(summary[@"truncated"]),
              @"schema.type", @"Plan truth values must be booleans");
    DigestField(summary, @"scenario");
    DigestField(summary, @"wireSHA256");
    SLRequire(duration >= delay && delivered <= advertised && wire >= delivered, @"plan.accounting",
              @"Plan timing or byte counts disagree");
    if ([summary[@"disconnect"] boolValue])
        SLRequire(wire == 0 && segments == 0 && delivered == 0, @"plan.accounting",
                  @"Disconnect plan must transmit no bytes");
    else
        SLRequire(wire > 0 && segments == 1 + (delivered + chunk - 1) / chunk, @"plan.accounting",
                  @"Plan segment count disagrees with its entity and chunk size");
    if ([summary[@"truncated"] boolValue])
        SLRequire(delivered < advertised, @"plan.accounting",
                  @"Truncated plan must send fewer entity bytes than advertised");
}
