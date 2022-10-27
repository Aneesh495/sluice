#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/// A delivery receipt measures bytes accepted by the local socket. It does not
/// claim that an application on the peer read or committed those bytes.
FOUNDATION_EXPORT NSDictionary *SLMakeReceipt(NSString *session, NSString *mode, NSString *identity,
                                              uint64_t occurrence, NSString *_Nullable fixture,
                                              NSDictionary *_Nullable plan,
                                              NSUInteger acceptedBytes, uint64_t elapsedUS,
                                              NSString *outcome, NSString *_Nullable errorCode);
FOUNDATION_EXPORT void SLValidateReceipt(NSDictionary *receipt);
NS_ASSUME_NONNULL_END
