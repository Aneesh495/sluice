#import "SLMessage.h"
#import "SLTarget.h"
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSData *SLWireResponseHead(SLMessage *message, NSUInteger advertisedLength);
FOUNDATION_EXPORT NSData *SLWireRequest(SLMessage *message, SLEndpoint *endpoint);
NS_ASSUME_NONNULL_END
