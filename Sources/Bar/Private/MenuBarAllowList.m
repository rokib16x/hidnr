#import "MenuBarAllowList.h"

#import <dlfcn.h>
#import <objc/message.h>

static NSString *const kFrameworkPath = @"/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore";
static NSString *const kConfigClass = @"MBAssessmentModeConfiguration";
static NSString *const kAssertionClass = @"MBAssessmentModeAssertion";

static NSError *HNError(NSString *message) {
    return [NSError errorWithDomain:@"hidnr.allowlist" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation HNMenuBarAllowList

+ (SEL)configInitSelector { return NSSelectorFromString(@"initWithAllowedSystemItems:allowedBundleIdentifiers:"); }
+ (SEL)activateSelector   { return NSSelectorFromString(@"activateWithConfiguration:completionHandler:"); }
+ (SEL)invalidateSelector { return NSSelectorFromString(@"invalidate"); }

+ (BOOL)isAvailable {
    static BOOL available = NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (dlopen(kFrameworkPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL) == NULL) {
            return;
        }
        Class config = NSClassFromString(kConfigClass);
        Class assertion = NSClassFromString(kAssertionClass);
        available = config != nil && assertion != nil
            && [config instancesRespondToSelector:[self configInitSelector]]
            && [assertion instancesRespondToSelector:[self activateSelector]]
            && [assertion instancesRespondToSelector:[self invalidateSelector]];
    });
    return available;
}

+ (void)allowSystemItems:(NSArray<NSNumber *> *)systemItems
                    apps:(NSArray<NSString *> *)bundleIdentifiers
              completion:(void (^)(id _Nullable, NSError * _Nullable))completion {
    void (^onMain)(id, NSError *) = ^(id token, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(token, error); });
    };
    if (![self isAvailable]) {
        onMain(nil, HNError(@"MenuBarClientCore is not available on this macOS"));
        return;
    }
    @try {
        // The framework indexes into both lists, so they must be real arrays.
        typedef id (*InitFn)(id, SEL, NSArray *, NSArray *);
        id config = ((InitFn)objc_msgSend)([NSClassFromString(kConfigClass) alloc], [self configInitSelector],
                                           [NSArray arrayWithArray:systemItems],
                                           [NSArray arrayWithArray:bundleIdentifiers]);
        id assertion = [[NSClassFromString(kAssertionClass) alloc] init];
        if (config == nil || assertion == nil) {
            onMain(nil, HNError(@"Could not build the allow-list"));
            return;
        }
        typedef void (*ActivateFn)(id, SEL, id, void (^)(NSError *));
        ((ActivateFn)objc_msgSend)(assertion, [self activateSelector], config, ^(NSError *error) {
            onMain(error == nil ? assertion : nil, error);
        });
    } @catch (NSException *exception) {
        onMain(nil, HNError([NSString stringWithFormat:@"%@: %@", exception.name, exception.reason]));
    }
}

+ (void)releaseToken:(id)token {
    @try {
        if ([token respondsToSelector:[self invalidateSelector]]) {
            ((void (*)(id, SEL))objc_msgSend)(token, [self invalidateSelector]);
        }
    } @catch (NSException *exception) {
        NSLog(@"hidnr: releasing the allow-list raised %@", exception.reason);
    }
}

@end
