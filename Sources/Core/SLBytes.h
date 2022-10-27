#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSData *SLUTF8(NSString *string);
FOUNDATION_EXPORT NSString *SLDecodeUTF8(NSData *data);
FOUNDATION_EXPORT NSString *SLSHA256(NSData *data);
FOUNDATION_EXPORT NSData *SLReadFile(NSString *path, NSUInteger limit);
FOUNDATION_EXPORT void SLAtomicWrite(NSData *data, NSString *path);
FOUNDATION_EXPORT NSUInteger SLFindBytes(NSData *data, const char *needle, NSUInteger length,
                                         NSUInteger start);
FOUNDATION_EXPORT BOOL SLToken(NSString *value);
FOUNDATION_EXPORT BOOL SLFieldValue(NSString *value);
NS_ASSUME_NONNULL_END
