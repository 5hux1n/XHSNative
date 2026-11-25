//
//  XHSNativeLegacyHooks.xm
//  XHSNative
//
//  仅 iOS < 26 启用的独立 Logos Hooks
//
#import <UIKit/UIKit.h>
#import "XHSNativeConfig.h"
#import "XHSNativeHeaders.h"
#import "XHSNativeLegacy.h"

@interface XYTabBarItem : UITabBarItem
@end

@interface XYPageScrollView : UIScrollView
@end

%group XHSNativeLegacy

%hook XYTabBarItem

- (void)setBadgeValue:(NSString *)badgeValue {
    %orig;
    if (XHSNativeConfig.shared.pages.count) {
        [XHSNativeLegacy layoutLegacyTabBar:XHSNativeConfig.shared.tabBarController.tabBar];
    }
}

%end

%hook XYPageScrollView

- (void)layoutSubviews {
    %orig;
    UIView *homeBar = XHSNativeConfig.shared.homeBar;
    if (homeBar && self.pagingEnabled && [self isDescendantOfView:homeBar.superview]) {
        [XHSNativeLegacy extendHomeFeedUnderNaviBar:homeBar];
    }
}

%end

%hook UIScrollView

- (void)_notifyDidScroll {
    %orig;
    static BOOL syncing = NO;
    UIView *homeBar = XHSNativeConfig.shared.homeBar;
    if (syncing || !homeBar || !self.window || self.window != homeBar.window ||
        self.pagingEnabled || CGRectGetHeight(self.bounds) < 200 || ![self isDescendantOfView:homeBar.superview]) {
        return;
    }
    syncing = YES;
    [XHSNativeLegacy extendHomeFeedUnderNaviBar:homeBar];
    syncing = NO;
}

%end

%end

%ctor {
    NSBundle *bundle = NSBundle.mainBundle;
    if (![bundle.bundleIdentifier hasPrefix:@"com.xingin.discover"] && ![[bundle objectForInfoDictionaryKey:@"CFBundleExecutable"] isEqual:@"discover"]) return;
    if (![XHSNativeLegacy isLiquidGlassOS]) {
        %init(XHSNativeLegacy);
    }
}
