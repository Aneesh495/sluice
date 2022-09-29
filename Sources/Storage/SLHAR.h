#import "SLFixture.h"
NS_ASSUME_NONNULL_BEGIN
/// HAR is an import boundary. Entries are decoded into messages, then pass
/// through exactly the same privacy filter as live network observations.
FOUNDATION_EXPORT NSArray<SLFixture *> *SLHARImport(NSData *data, SLPrivacy *privacy);
NS_ASSUME_NONNULL_END
