#import "SLMessage.h"
NS_ASSUME_NONNULL_BEGIN
@interface SLHTTPParser : NSObject
@property(nonatomic, readonly, nullable) SLMessage *message;
@property(nonatomic, readonly) BOOL complete;
@property(nonatomic, readonly) BOOL headComplete;
- (instancetype)initRequest:(BOOL)request responseToHEAD:(BOOL)head;
- (void)feed:(NSData *)data;
- (void)endOfFile;
@end
NS_ASSUME_NONNULL_END
