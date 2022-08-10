#import "SLDeliveryPlan.h"
#import "SLWire.h"
#import "SLRandom.h"
#import "SLBytes.h"
#import "SLError.h"
@implementation SLDeliveryPlan {
    NSUInteger _headBytes;
    NSUInteger _bodyBytes;
    NSUInteger _chunkBytes;
    NSUInteger _rate;
}
- (instancetype)initResponse:(SLMessage *)response request:(SLMessage *)request rule:(SLRule *)rule scenario:(SLScenario *)scenario identity:(NSString *)identity occurrence:(uint64_t)occurrence {
    if ((self=[super init])) {
        SLAction *action=rule ? rule.action : [[SLAction alloc] initWithDocument:@{}];
        _response=[action apply:response];
        uint64_t jitter=action.jitterMS ? SLDraw(scenario.seed,rule.identifier,identity,occurrence,@"jitter")%(action.jitterMS+1) : 0;
        _delayUS=(action.delayMS+jitter)*1000;
        BOOL noBody=[request.method isEqual:@"HEAD"] || _response.status==204 || _response.status==304;
        NSUInteger advertised=_response.body.length;
        NSData *body=noBody?NSData.data:_response.body;
        if (action.truncateAfter) body=[body subdataWithRange:NSMakeRange(0,MIN(body.length,action.truncateAfter.unsignedIntegerValue))];
        NSData *head=SLWireResponseHead(_response,advertised);
        _headBytes=action.disconnect?0:head.length; _bodyBytes=action.disconnect?0:body.length;
        _chunkBytes=action.chunkBytes; _rate=action.bytesPerSecond;
        NSMutableData *wire=[NSMutableData data];
        if (!action.disconnect) { [wire appendData:head]; [wire appendData:body]; }
        _wire=[wire copy]; _segmentCount=_headBytes ? 1+(_bodyBytes+_chunkBytes-1)/_chunkBytes : 0;
        _durationUS=_segmentCount ? [self dueUSAt:_segmentCount-1] : _delayUS;
        SLRequire(_durationUS<=120000000,@"plan.duration",@"Delivery plan exceeds the 120 second lifetime budget");
        _summary=@{@"version":@1,@"identity":identity,@"occurrence":@(occurrence),@"scenario":scenario.digest,@"rule":rule.identifier ?: @"passthrough",@"status":@(_response.status),@"delayUs":@(_delayUS),@"durationUs":@(_durationUS),@"advertisedBodyBytes":@(advertised),@"deliveredBodyBytes":@(_bodyBytes),@"wireBytes":@(_wire.length),@"wireSHA256":SLSHA256(_wire),@"segments":@(_segmentCount),@"chunkBytes":@(_chunkBytes),@"bytesPerSecond":@(_rate),@"disconnect":@(action.disconnect),@"truncated":@(!noBody && body.length<_response.body.length)};
    } return self;
}
- (NSRange)rangeAt:(NSUInteger)index {
    SLRequire(index<self.segmentCount,@"plan.index",@"Delivery segment index is out of range");
    if (!index) return NSMakeRange(0,_headBytes);
    NSUInteger offset=(index-1)*_chunkBytes;
    return NSMakeRange(_headBytes+offset,MIN(_chunkBytes,_bodyBytes-offset));
}
- (uint64_t)dueUSAt:(NSUInteger)index {
    SLRequire(index<self.segmentCount,@"plan.index",@"Delivery segment index is out of range");
    uint64_t offset=index ? (index-1)*_chunkBytes : 0;
    return self.delayUS+(_rate ? (offset*1000000+_rate-1)/_rate : 0);
}
@end
