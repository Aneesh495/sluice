#import "SLMessage.h"
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT SLMessage *SLParseHead(NSData *head, BOOL request);
FOUNDATION_EXPORT NSUInteger SLContentLength(SLHeaders *headers, BOOL *present);
NS_ASSUME_NONNULL_END
