//
//  XHSNativeLegacyHooks.xm
//  XHSNative
//
//  仅 iOS < 26 启用的独立 Logos Hooks
//
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "XHSNativeConfig.h"
#import "XHSNativeHeaders.h"
#import "XHSNativeHelper.h"
#import "XHSNativeLegacy.h"

@interface XYTabBarItem : UITabBarItem
@end

@interface XYPageScrollView : UIScrollView
@end

%group XHSNativeLegacy

%hook XYTabBarItem

- (NSString *)title {
    if (XHSNativeConfig.shared.isTabTitleShown) {
        struct objc_super sup = {self, UITabBarItem.class};
        return ((NSString *(*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, @selector(title));
    }
    return %orig;
}

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
    [XHSNativeLegacy updateSoftEdgeFadesForScrollView:self];
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

%hook XYSearchBarV2Compat

- (void)didMoveToWindow {
    %orig;
    if (((UIView *)self).window) {
        [XHSNativeLegacy prepareLegacySearchBar:(UIView *)self];
        [(UIView *)self setNeedsLayout];
    }
}

- (void)layoutSubviews {
    [XHSNativeLegacy prepareLegacySearchBar:(UIView *)self];
    %orig;
    [XHSNativeLegacy layoutLegacySearchBar:(UIView *)self];
}

%end

%hook XYPHNavigationViewController

- (void)viewDidLayoutSubviews {
    %orig;
    XYTabbarController *controller = XHSNativeConfig.shared.tabBarController;
    if (!controller || self.parentViewController != controller || !XHSNativeConfig.shared.tabsDirty) return;
    if (self.transitionCoordinator) {
        [self.transitionCoordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> ctx) {
            if (!ctx.isCancelled && XHSNativeConfig.shared.tabsDirty) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (XHSNativeConfig.shared.tabsDirty && ![XHSNativeLegacy isControllerTabBarHidden:controller]) {
                        [XHSNativeLegacy rebuildLegacyTabs];
                    }
                });
            }
        }];
    } else if (![XHSNativeLegacy isControllerTabBarHidden:controller]) {
        [XHSNativeLegacy rebuildLegacyTabs];
    }
}

%end

%end

#pragma mark - 广告笔记底栏与页面恢复兼容

%group XHSNativeAdNoteCompat

%hook XYAdsGoodsNoteBottomViewCompat

- (void)didMoveToWindow {
    %orig;
    if (((UIView *)self).window) [XHSNativeLegacy layoutAdNoteBottom:(UIView *)self];
}

- (void)layoutSubviews {
    %orig;
    [XHSNativeLegacy layoutAdNoteBottom:(UIView *)self];
}

%end

%hook XYAdsLeadsBottomBarCompat

- (void)didMoveToWindow {
    %orig;
    if (((UIView *)self).window) [XHSNativeLegacy layoutAdNoteBottom:(UIView *)self];
}

- (void)layoutSubviews {
    %orig;
    [XHSNativeLegacy layoutAdNoteBottom:(UIView *)self];
}

%end

%hook XYNoteDetailPageCompat

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    UIViewController *vc = (UIViewController *)self;
    if (![XHSNativeConfig.shared boolForKey:kXHSNativeGlassNote]) {
        [XHSNativeLegacy restoreLegacyDecorationsInView:vc.view];
    } else {
        [vc.view setNeedsLayout];
    }
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (![XHSNativeConfig.shared boolForKey:kXHSNativeGlassNote]) {
        [XHSNativeLegacy restoreLegacyDecorationsInView:((UIViewController *)self).view];
    }
}

%end

%hook XYVFHeadViewCompat

- (void)layoutSubviews {
    %orig;
    if (![XHSNativeConfig.shared boolForKey:kXHSNativeGlassVideo]) {
        [XHSNativeLegacy restoreLegacyDecorationsInView:(UIView *)self];
    }
}

%end

%hook XYVFBottomEngageViewCompat

- (void)layoutSubviews {
    %orig;
    if (![XHSNativeConfig.shared boolForKey:kXHSNativeGlassVideo]) {
        [XHSNativeLegacy restoreLegacyDecorationsInView:(UIView *)self];
    }
}

%end

%hook XYMessageOpenNoticeAlertViewCompat

- (void)didMoveToSuperview {
    %orig;
    UIView *view = (UIView *)self;
    view.hidden = YES;
    view.alpha = 0;
    view.userInteractionEnabled = NO;
}

- (void)setHidden:(BOOL)hidden {
    %orig(YES);
}

- (void)layoutSubviews {
    %orig;
    UIView *view = (UIView *)self;
    view.hidden = YES;
    view.alpha = 0;
    view.userInteractionEnabled = NO;
}

%end

%end

%ctor {
    NSBundle *bundle = NSBundle.mainBundle;
    if (![bundle.bundleIdentifier hasPrefix:@"com.xingin.discover"] && ![[bundle objectForInfoDictionaryKey:@"CFBundleExecutable"] isEqual:@"discover"]) return;
    if (![XHSNativeLegacy isLiquidGlassOS]) {
        %init(XHSNativeLegacy,
              XYSearchBarV2Compat = objc_getClass("XYSearchBar.XYSearchBarV2"));
        %init(XHSNativeAdNoteCompat,
              XYAdsGoodsNoteBottomViewCompat = objc_getClass("XYAdsBusiness.AdsGoodsNoteBottomView"),
              XYAdsLeadsBottomBarCompat = objc_getClass("XYAdsLeadsBottomBar"),
              XYNoteDetailPageCompat = objc_getClass("XYNoteModule.NoteDetailPageInterface"),
              XYVFHeadViewCompat = objc_getClass("XYOldNoteModule.VFHeadView"),
              XYVFBottomEngageViewCompat = objc_getClass("XYOldNoteModule.VFBottomEngageView"),
              XYMessageOpenNoticeAlertViewCompat = objc_getClass("XYMessageUIKit.MessageOpenNoticeAlertView"));
    }
}
