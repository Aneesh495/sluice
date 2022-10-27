#import "SLHTTPParser.h"
#import "SLSession.h"
NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSInteger, SLConnectionState) {
    SLReadingRequest,
    SLConnectingOrigin,
    SLWritingOrigin,
    SLReadingOrigin,
    SLDeliveringResponse,
    SLConnectionClosed
};
/// The reactor is the sole descriptor owner. A connection never escapes its
/// thread. Closing is idempotent, including exceptional destruction paths.
@interface SLConnection : NSObject
@property(nonatomic) int clientFD;
@property(nonatomic) int originFD;
@property(nonatomic) SLConnectionState state;
@property(nonatomic) SLHTTPParser *requestParser;
@property(nonatomic, nullable) SLHTTPParser *responseParser;
@property(nonatomic, nullable) SLRequestContext *context;
@property(nonatomic, nullable) SLDeliveryPlan *plan;
@property(nonatomic, nullable) NSData *originWire;
@property(nonatomic) NSUInteger originWritten;
@property(nonatomic) NSUInteger acceptedBytes;
@property(nonatomic) NSUInteger segment;
@property(nonatomic) NSUInteger segmentWritten;
@property(nonatomic) uint64_t startedUS;
@property(nonatomic) uint64_t activeUS;
@property(nonatomic) uint64_t planStartUS;
@property(nonatomic) NSUInteger addressIndex;
@property(nonatomic) BOOL receiptWritten;
@property(nonatomic, nullable) NSString *errorCode;
@property(nonatomic, copy) NSString *outcome;
- (instancetype)initWithSocket:(int)fd;
- (void)closeOrigin;
- (void)close;
@end
NS_ASSUME_NONNULL_END
