#import <Foundation/Foundation.h>
#import "SLTarget.h"
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT uint64_t SLNowUS(void);
FOUNDATION_EXPORT void SLNonblocking(int fd);
FOUNDATION_EXPORT int SLListen(uint16_t port, uint16_t *actualPort);
FOUNDATION_EXPORT NSArray<NSData *> *SLResolve(SLEndpoint *endpoint);
FOUNDATION_EXPORT int SLConnect(NSData *address);
FOUNDATION_EXPORT BOOL SLWouldBlock(void);
NS_ASSUME_NONNULL_END
