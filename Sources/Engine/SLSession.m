#import "SLSession.h"
#import "SLError.h"
@implementation SLRequestContext
@end
@implementation SLSession {
    NSMutableDictionary<NSString *,NSNumber *> *_occurrences;
    SLReplayIndex *_index;
    NSString *_fixture;
}
- (instancetype)initMode:(NSString *)mode store:(SLStore *)store privacy:(SLPrivacy *)privacy scenario:(SLScenario *)scenario fixture:(NSString *)fixture {
    if ((self=[super init])) {
        SLRequire([@[@"record",@"replay"] containsObject:mode],@"session.mode",@"Session mode must be record or replay");
        _identifier=NSUUID.UUID.UUIDString.lowercaseString; _mode=[mode copy]; _store=store; _privacy=privacy; _scenario=scenario; _fixture=[fixture copy];
        _occurrences=[NSMutableDictionary dictionary];
        if ([mode isEqual:@"replay"]) _index=[[SLReplayIndex alloc] initWithFixtures:store.fixtures privacy:privacy];
    } return self;
}
- (SLRequestContext *)begin:(SLMessage *)request {
    NSDictionary *filtered=[self.privacy message:request];
    SLRequestContext *context=[SLRequestContext new]; context.identity=SLRequestIdentity(filtered);
    SLRequire(_occurrences[context.identity]!=nil || _occurrences.count<10000,@"session.capacity",@"Session request identity limit reached");
    context.occurrence=[_occurrences[context.identity] unsignedLongLongValue]+1;
    SLRequire(context.occurrence<=INT64_MAX,@"session.capacity",@"Session occurrence counter exhausted");
    _occurrences[context.identity]=@(context.occurrence); context.filteredRequest=SLMessageFromDocument(filtered,YES);
    context.rule=[self.scenario ruleFor:context.filteredRequest identity:context.identity occurrence:context.occurrence];
    return context;
}
- (SLMessage *)replay:(SLRequestContext *)context {
    SLRequire(_index!=nil,@"session.mode",@"Session is not in replay mode");
    SLFixture *fixture=[_index select:context.identity identifier:_fixture]; context.fixture=fixture.identifier; return [fixture.response copy];
}
- (SLDeliveryPlan *)complete:(SLRequestContext *)context request:(SLMessage *)request response:(SLMessage *)response {
    if ([self.mode isEqual:@"record"]) context.fixture=[self.store saveFixture:[SLFixture captureRequest:request response:response privacy:self.privacy]];
    return [[SLDeliveryPlan alloc] initResponse:response request:request rule:context.rule scenario:self.scenario identity:context.identity occurrence:context.occurrence];
}
@end
