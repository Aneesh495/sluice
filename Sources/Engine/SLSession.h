#import "SLStore.h"
#import "SLDeliveryPlan.h"
#import "SLReplayIndex.h"
NS_ASSUME_NONNULL_BEGIN
@interface SLRequestContext : NSObject
@property(nonatomic) NSString *identity;
@property(nonatomic) uint64_t occurrence;
@property(nonatomic) SLMessage *filteredRequest;
@property(nonatomic, nullable) NSString *fixture;
@property(nonatomic, nullable) SLRule *rule;
@end
/// A session is confined to the reactor thread. It owns ordinal counters and a
/// frozen replay index; unrelated identities cannot shift each other's faults.
@interface SLSession : NSObject
@property(nonatomic, readonly) NSString *identifier;
@property(nonatomic, readonly) NSString *mode;
@property(nonatomic, readonly) SLStore *store;
@property(nonatomic, readonly) SLPrivacy *privacy;
@property(nonatomic, readonly) SLScenario *scenario;
- (instancetype)initMode:(NSString *)mode
                   store:(SLStore *)store
                 privacy:(SLPrivacy *)privacy
                scenario:(SLScenario *)scenario
                 fixture:(nullable NSString *)fixture;
- (SLRequestContext *)begin:(SLMessage *)request;
- (SLMessage *)replay:(SLRequestContext *)context;
- (SLDeliveryPlan *)complete:(SLRequestContext *)context
                     request:(SLMessage *)request
                    response:(SLMessage *)response;
@end
NS_ASSUME_NONNULL_END
