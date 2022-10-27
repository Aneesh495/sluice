#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface SLArguments : NSObject
@property(nonatomic, readonly) NSArray<NSString *> *operands;
@property(nonatomic, readonly) NSDictionary<NSString *, NSString *> *options;
- (instancetype)initWithArguments:(NSArray<NSString *> *)arguments
                           values:(NSArray<NSString *> *)values
                            flags:(NSArray<NSString *> *)flags;
- (NSString *)required:(NSString *)name;
- (nullable NSString *)value:(NSString *)name;
- (BOOL)has:(NSString *)name;
- (int64_t)integer:(NSString *)name
          fallback:(int64_t)fallback
           minimum:(int64_t)minimum
           maximum:(int64_t)maximum;
@end
NS_ASSUME_NONNULL_END
