#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/// JSON reader rejects duplicate keys, invalid UTF-8, trailing input, excessive
/// nesting, and excessive node counts before a document reaches its schema.
FOUNDATION_EXPORT id SLJSONRead(NSData *data);
FOUNDATION_EXPORT NSData *SLJSONData(id object);
FOUNDATION_EXPORT NSString *SLJSONString(id object);
NS_ASSUME_NONNULL_END
