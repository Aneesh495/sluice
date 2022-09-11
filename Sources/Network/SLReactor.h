#import "SLConnection.h"
#import "SLTarget.h"
NS_ASSUME_NONNULL_BEGIN
@interface SLReactor : NSObject
@property(nonatomic, readonly) uint16_t port;
@property(nonatomic, readonly) NSUInteger activeConnections;
@property(nonatomic, readonly) NSUInteger completedConnections;
@property(nonatomic, readonly, nullable) NSString *fatalError;
@property(atomic, readonly) BOOL running;
- (instancetype)initSession:(SLSession *)session upstream:(nullable SLEndpoint *)upstream port:(uint16_t)port;
/// Blocks the calling background thread. ready runs on that same thread.
- (void)runReady:(void (^)(uint16_t port))ready;
/// Thread-safe self-pipe wakeup; safe from a UI action, not a signal handler.
- (void)stop;
@end
NS_ASSUME_NONNULL_END
