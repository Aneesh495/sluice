#import "SLMatch.h"
#import "SLAction.h"
NS_ASSUME_NONNULL_BEGIN
@interface SLRule : NSObject
@property(nonatomic, readonly) NSString *identifier;
@property(nonatomic, readonly) SLMatch *match;
@property(nonatomic, readonly) SLAction *action;
@property(nonatomic, readonly) NSUInteger after;
@property(nonatomic, readonly) NSUInteger every;
@property(nonatomic, readonly) NSUInteger limit;
@property(nonatomic, readonly) NSUInteger chance;
- (instancetype)initWithDocument:(NSDictionary *)document;
- (BOOL)selectsOccurrence:(uint64_t)occurrence identity:(NSString *)identity seed:(uint64_t)seed;
@end
@interface SLScenario : NSObject
@property(nonatomic, readonly) NSDictionary *document;
@property(nonatomic, readonly) NSString *name;
@property(nonatomic, readonly) NSString *digest;
@property(nonatomic, readonly) uint64_t seed;
@property(nonatomic, readonly) NSArray<SLRule *> *rules;
- (instancetype)initWithDocument:(NSDictionary *)document;
+ (instancetype)passthrough;
- (nullable SLRule *)ruleFor:(SLMessage *)request identity:(NSString *)identity occurrence:(uint64_t)occurrence;
@end
NS_ASSUME_NONNULL_END
