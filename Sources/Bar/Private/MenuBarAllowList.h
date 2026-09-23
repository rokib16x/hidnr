#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Thin wrapper around macOS 27's private MenuBarClientCore framework.
///
/// macOS 27 can limit the menu bar to an allow-list of apps (it uses this for
/// assessment / exam mode). hidnr uses the same switch to hide everything the
/// user put on the hidden side. The framework is private, so everything is looked
/// up at runtime and any mismatch reports "unavailable" instead of crashing.
/// Written in Objective-C so exceptions from a changed API can be caught.
@interface HNMenuBarAllowList : NSObject

/// YES when the framework, its two classes and the selectors hidnr calls all exist.
+ (BOOL)isAvailable;

/// Show only these system items and apps. Everything else in the menu bar is
/// hidden until the returned token is released or hidnr quits. The completion
/// runs on the main queue with either a token or an error.
+ (void)allowSystemItems:(NSArray<NSNumber *> *)systemItems
                    apps:(NSArray<NSString *> *)bundleIdentifiers
              completion:(void (^)(id _Nullable token, NSError * _Nullable error))completion;

/// Ends a restriction started with +allowSystemItems:apps:completion:.
+ (void)releaseToken:(id)token;

@end

NS_ASSUME_NONNULL_END
