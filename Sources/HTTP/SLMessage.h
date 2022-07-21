#import <Foundation/Foundation.h>
#import "SLHeaders.h"
NS_ASSUME_NONNULL_BEGIN
@interface SLMessage : NSObject <NSCopying>
@property(nonatomic) BOOL request;
@property(nonatomic, copy) NSString *method;
@property(nonatomic, copy) NSString *target;
@property(nonatomic) NSInteger status;
@property(nonatomic, copy) NSString *reason;
@property(nonatomic, copy) NSString *version;
@property(nonatomic) SLHeaders *headers;
@property(nonatomic, copy) NSData *body;
+ (instancetype)response:(NSInteger)status body:(NSData *)body contentType:(NSString *)contentType;
@end
NS_ASSUME_NONNULL_END
