//
//  XHSNativeLegacy.h
//  XHSNative
//
//  iOS < 26 仿液态玻璃适配与兼容层（独立于上游原生 iOS 26+ 实现）
//
#import <UIKit/UIKit.h>
#import "XHSNativeConfig.h"

@class XYTabbarController, XYMHomeNaviBar, XYPFProfileV2NavigationBar;

@interface XHSNativeConfig (Legacy)
@property (nonatomic, assign) CGFloat blurPercent;
@end

@interface XHSNativeLegacy : NSObject

+ (BOOL)isLiquidGlassOS;

#pragma mark - 仿液态玻璃底板与渐隐边缘

+ (UIView *)plateOn:(UIView *)owner key:(const void *)key below:(UIView *)below frame:(CGRect)frame bar:(NSString *)bar;
+ (void)refreshAllPlates;
+ (void)darkenGlass:(UIView *)glass;
+ (BOOL)isGlassView:(UIView *)view;
+ (void)applySoftEdgeFadeOn:(UIView *)bar key:(const void *)key fromTop:(BOOL)fromTop extraHeight:(CGFloat)extraHeight;

#pragma mark - 按钮与底栏

+ (UIButton *)glassIconButtonWithSymbol:(NSString *)symbolName label:(NSString *)label handler:(void (^)(void))handler;
+ (UIViewController *)legacyPageForName:(NSString *)name;
+ (BOOL)isControllerTabBarHidden:(UITabBarController *)controller;
+ (void)rebuildLegacyTabs;
+ (void)layoutLegacyTabBar:(UITabBar *)bar;
+ (void)setLegacyTabBarMinimized:(BOOL)minimized;
+ (void)handleScrollPan:(UIPanGestureRecognizer *)pan inPage:(UIViewController *)page;

#pragma mark - 首页 / 个人页 / 笔记页低版本布局

+ (void)extendHomeFeedUnderNaviBar:(UIView *)naviBar;
+ (void)layoutProfileBar:(XYPFProfileV2NavigationBar *)bar;
+ (void)adjustNoteBottomInStack:(UIView *)stack;

@end
