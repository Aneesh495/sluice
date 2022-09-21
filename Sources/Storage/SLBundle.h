#import "SLFixture.h"
NS_ASSUME_NONNULL_BEGIN
/// Portable fixtures use canonical checksums, not signatures. Checksums detect
/// damage and accidental edits; they do not authenticate a sender.
FOUNDATION_EXPORT NSData *SLBundleEncode(NSArray<SLFixture *> *fixtures);
FOUNDATION_EXPORT NSArray<SLFixture *> *SLBundleDecode(NSData *data);
NS_ASSUME_NONNULL_END
