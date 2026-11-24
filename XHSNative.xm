//
//  XHSNative
//
//  Copyright (c) 2026 huami. All rights reserved.
//  Channel: @huamidev
//  Created on: 2026/11/24
//
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <mach/mach.h>
#import <objc/message.h>
#import <objc/runtime.h>

#define XHSNativeVersion @"1.1(11250037)"

@interface XYTabbarController : UITabBarController
- (UIControl *)centerButton;
- (UIView *)customtabBar;
@end

@interface XYPHHomeTabbarController : XYTabbarController <UITabBarControllerDelegate>
@end

@interface XYPHNavigationViewController : UINavigationController
@end

@interface XYMHomeViewController : UIViewController
@end

@interface XYMHomeNaviBar : UIView
- (UIImageView *)background;
@end

@interface XYMHomeLayoutAdapter : NSObject
@end

@interface XYEXLiquidGlassNavigationAdapter : NSObject
@end

@interface XYLiquidGlass : NSObject
@end

@interface XYFollowBtn : UIButton
@end

@interface XYPMMessageCenterViewController : UIViewController
@end

@interface XYPFProfileViewController : UIViewController
@end

@interface XYSettingBaseViewController : UIViewController
- (UITableView *)tableView;
- (id)navBar;
- (id)vm;
@end

@interface XYPHSettingViewController : XYSettingBaseViewController
@end

@interface XYPHSettingTableViewModel : NSObject
- (id)blank;
@end

// 下面几个是 Swift 类，真名在 %ctor 里对上
@interface XYNativeSearchBar : UIView
@property (nonatomic) BOOL usesLiquidGlass;
@end

@interface XYPFProfileV2NavigationBar : UIView
- (UIView *)homeMenuButton;
- (UIView *)shareButton;
- (UIView *)scanButton;
- (UIView *)editButton;
- (BOOL)usesDuoNavigation;
@end

@interface XYPMChatBaseViewController : UIViewController
- (BOOL)isFloating;
@end

@interface XYCommentHalfBar : UIView
@end

@interface XYDeviceUtility : NSObject
@end

@interface XYMarketRootInterface : UIViewController
@end

@interface XYNoteDetailPage : UIViewController
@end

@interface XYLottieAnimationButton : UIButton
- (UIView *)lottieMaskView;
@end

@interface XYNoteInteractionView : UIView
- (XYLottieAnimationButton *)likeButton;
@end

@interface XYNoteDirectionView : UIView
@end

@interface XYVFHeadView : UIView
@end

@interface XYVFBottomEngageView : UIView
@end

@interface XHSNativeSettingsPage : XYSettingBaseViewController
@property (nonatomic, strong) id model;
@property (nonatomic, copy) NSString *mode;  // 空：主页面；order：标签顺序；其余是某一处玻璃的名字，选它的不透明度
- (void)reloadRows;
@end

#pragma mark - 设置项

static NSString *const kTabOrder = @"XHSNative.tabOrder";    // 标签顺序，存的是 index / shopping / message / me
static NSString *const kTabHidden = @"XHSNative.tabHidden";  // 隐藏的标签
static NSString *const kSearchTab = @"XHSNative.searchTab";  // 右侧的搜索
static NSString *const kMinimize = @"XHSNative.minimize";    // 滚动时收起底栏
static NSString *const kGlassNote = @"XHSNative.glass.note";
static NSString *const kGlassSearch = @"XHSNative.glass.search";
static NSString *const kGlassComments = @"XHSNative.glass.comments";
static NSString *const kGlassProfile = @"XHSNative.glass.profile";
static NSString *const kGlassChat = @"XHSNative.glass.chat";
static NSString *const kGlassMessages = @"XHSNative.glass.messages";
static NSString *const kGlassVideo = @"XHSNative.glass.video";

// 各处玻璃的不透明度（0 ~ 100），键是 XHSNative.fill.<位置>
static NSString *const kBarHome = @"home";
static NSString *const kBarNoteTop = @"noteTop";
static NSString *const kBarNoteBottom = @"noteBottom";
static NSString *const kBarVideoTop = @"videoTop";
static NSString *const kBarVideoBottom = @"videoBottom";

static BOOL prefBool(NSString *key, BOOL fallback) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:key];
    return value ? [value boolValue] : fallback;
}

static NSString *fillKey(NSString *bar) {
    return [@"XHSNative.fill." stringByAppendingString:bar];
}

static CGFloat fillOf(NSString *bar) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:fillKey(bar)];
    if (value) return MIN(MAX([value doubleValue], 0), 100);
    // 笔记底栏下面滚的是评论文字，默认压一半，其余默认纯玻璃
    return [bar isEqualToString:kBarNoteBottom] ? 50 : 0;
}

static NSArray<NSString *> *allTabs(void) {
    return @[@"index", @"shopping", @"message", @"me"];
}

static NSArray<NSString *> *tabOrder(void) {
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    for (NSString *name in [NSUserDefaults.standardUserDefaults stringArrayForKey:kTabOrder])
        if ([allTabs() containsObject:name] && ![order containsObject:name]) [order addObject:name];
    for (NSString *name in allTabs())
        if (![order containsObject:name]) [order addObject:name];
    return order;
}

static BOOL tabHidden(NSString *name) {
    if ([name isEqualToString:@"index"]) return NO;  // 首页不能藏，发布和搜索都挂在它上面
    return [[NSUserDefaults.standardUserDefaults stringArrayForKey:kTabHidden] containsObject:name];
}

#pragma mark - 玻璃底板

// 垫在一组现有控件后面的胶囊形玻璃，控件本身不动。frame 传空矩形表示收起。
static UIVisualEffectView *plate(UIView *owner, const void *key, UIView *below, CGRect frame, NSString *bar) {
    UIVisualEffectView *glass = objc_getAssociatedObject(owner, key);
    if (!glass) {
        glass = [[UIVisualEffectView alloc] initWithEffect:[UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular]];
        glass.cornerConfiguration = [UICornerConfiguration capsuleConfiguration];
        glass.userInteractionEnabled = NO;
        glass.contentView.layer.masksToBounds = YES;
        objc_setAssociatedObject(owner, key, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    BOOL empty = CGRectIsEmpty(frame) || !below.superview;
    if (glass.hidden != empty) glass.hidden = empty;
    if (empty) return glass;

    NSArray<UIView *> *siblings = below.superview.subviews;
    NSUInteger index = [siblings indexOfObjectIdenticalTo:below];
    if (glass.superview != below.superview || index == 0 || siblings[index - 1] != glass) [below.superview insertSubview:glass belowSubview:below];
    if (!CGRectEqualToRect(glass.frame, frame)) glass.frame = frame;

    // 不透明度：在玻璃上垫一层半透明的底色
    UIView *content = glass.contentView;
    NSInteger fill = (NSInteger)fillOf(bar);
    if (content.tag != fill + 1) {
        content.tag = fill + 1;
        content.backgroundColor = fill ? [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor colorWithRed:0.13 green:0.13 blue:0.15 alpha:fill / 100.0]
                                                                         : [UIColor colorWithWhite:1 alpha:fill / 100.0];
        }] : nil;
    }
    content.layer.cornerRadius = CGRectGetHeight(frame) / 2;
    return glass;
}

static void clearBackground(UIView *view) {
    if (view.backgroundColor && ![view.backgroundColor isEqual:UIColor.clearColor]) view.backgroundColor = UIColor.clearColor;
}

static BOOL isVisible(UIView *view) {
    return view && !view.hidden && view.alpha > 0.01 && CGRectGetWidth(view.bounds) > 0 && CGRectGetHeight(view.bounds) > 0;
}

#pragma mark - 底栏

// 小红书的底栏是自己画的一条，盖在系统 UITabBar 上，再把系统的内容藏掉。
// 这里反过来：藏掉它画的那条，放出系统的，用 UITab 重新排一遍，右侧加系统的搜索标签。
// 页面、选中逻辑、角标仍然走小红书自己的，只是换了显示的那一层。

static __weak XYTabbarController *gTabBarController;
static __weak UIControl *gSearchButton;                // 首页顶栏原来的搜索按钮，被我们收起来了，但还能替用户点
static NSArray<UIViewController *> *gPages;            // 小红书自己的页面顺序：首页 市集 消息 我
static NSArray<NSString *> *gPageNames;
static BOOL gRebuilding;

// 调用是不是来自小红书主程序（而不是系统框架）
static BOOL calledFromApp(void *address) {
    static const void *app;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        for (uint32_t i = 0; i < _dyld_image_count() && !app; i++)
            if (((const struct mach_header_64 *)_dyld_get_image_header(i))->filetype == MH_EXECUTE) app = _dyld_get_image_header(i);
    });
    Dl_info info;
    return dladdr(address, &info) && info.dli_fbase == app;
}

// 小红书图标库里的图标对象：XYThemeManager.defaultManager.icon.home_b
static id themeGlyph(NSString *name) {
    Class managerClass = objc_getClass("XYThemeManager");
    if (![managerClass respondsToSelector:NSSelectorFromString(@"defaultManager")]) return nil;
    id manager = ((id (*)(id, SEL))objc_msgSend)(managerClass, NSSelectorFromString(@"defaultManager"));
    if (![manager respondsToSelector:NSSelectorFromString(@"icon")]) return nil;
    id set = ((id (*)(id, SEL))objc_msgSend)(manager, NSSelectorFromString(@"icon"));
    return [set respondsToSelector:NSSelectorFromString(name)] ? ((id (*)(id, SEL))objc_msgSend)(set, NSSelectorFromString(name)) : nil;
}

// 取成图片的写法是 .size(28).image
static UIImage *themeIcon(NSString *name) {
    id glyph = themeGlyph(name);
    if (![glyph respondsToSelector:NSSelectorFromString(@"size")]) return nil;
    id (^sized)(CGFloat) = ((id (*)(id, SEL))objc_msgSend)(glyph, NSSelectorFromString(@"size"));
    id result = sized ? sized(28) : nil;
    if (![result respondsToSelector:NSSelectorFromString(@"image")]) return nil;
    UIImage *image = ((id (*)(id, SEL))objc_msgSend)(result, NSSelectorFromString(@"image"));
    return [image isKindOfClass:UIImage.class] ? [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] : nil;
}

static UIImage *tabIcon(NSString *name, BOOL selected) {
    NSDictionary *theme = @{@"index": @"home", @"shopping": @"store", @"message": @"chat", @"me": @"me"};
    NSDictionary *symbols = @{@"index": @"house", @"shopping": @"bag", @"message": @"message", @"me": @"person"};
    UIImage *image = themeIcon([theme[name] stringByAppendingString:selected ? @"_f" : @"_b"]);
    return image ?: [UIImage systemImageNamed:selected ? [symbols[name] stringByAppendingString:@".fill"] : symbols[name]];
}

// 当前显示着的、对应某个页面的标签
static UITab *pageTab(NSString *name) {
    for (UITab *tab in gTabBarController.tabs)
        if ([tab.identifier isEqualToString:name]) return tab;
    return nil;
}

static BOOL gTabsDirty;
static UIViewController *gSearchPage;  // 搜索标签挂的空页面，它不会真的显示

static void rebuildTabs(void) {
    XYTabbarController *controller = gTabBarController;
    if (!controller || !gPages.count) return;
    // 底栏被二级页面盖住时（比如正在设置页里改）先记一笔，等它重新露出来再换
    gTabsDirty = controller.isTabBarHidden;
    if (gTabsDirty) return;

    // 每次都建新的标签对象：沿用旧对象重排的话，系统会把留下来的那几个画成灰的
    NSString *selected = controller.selectedTab.identifier;
    NSMutableArray<UITab *> *tabs = [NSMutableArray array];
    for (NSString *name in tabOrder()) {
        NSUInteger index = [gPageNames indexOfObject:name];
        if (index == NSNotFound || tabHidden(name)) continue;
        UIViewController *page = gPages[index];
        UITab *tab = [[UITab alloc] initWithTitle:@"" image:tabIcon(name, NO) identifier:name viewControllerProvider:^UIViewController *(UITab *t) { return page; }];
        if ([tab respondsToSelector:@selector(setSelectedImage:)]) [(id)tab setSelectedImage:tabIcon(name, YES)];
        tab.badgeValue = pageTab(name).badgeValue;
        [tabs addObject:tab];
    }
    if (prefBool(kSearchTab, YES)) {
        // 系统的搜索标签会自己单独排在右边。它不切页面，点了直接开小红书的搜索，见 shouldSelectTab
        if (!gSearchPage) gSearchPage = [UIViewController new];
        UIViewController *page = gSearchPage;
        UISearchTab *search = [[UISearchTab alloc] initWithViewControllerProvider:^UIViewController *(UITab *t) { return page; }];
        search.automaticallyActivatesSearch = YES;
        [tabs addObject:search];
    }
    gRebuilding = YES;
    [controller setTabs:tabs animated:NO];
    // 旧栏保留给发布和角标使用。其他插件可能在布局时重新显示它。
    if (pageTab(@"index")) controller.customtabBar.alpha = 0;
    UITab *restored = selected ? pageTab(selected) : nil;
    if (restored) controller.selectedTab = restored;
    controller.tabBarMinimizeBehavior = prefBool(kMinimize, YES) ? UITabBarMinimizeBehaviorOnScrollDown : UITabBarMinimizeBehaviorNever;
    gRebuilding = NO;
}

// 等同于点原来的加号
static void openPublish(void) {
    UIControl *button = [gTabBarController respondsToSelector:@selector(centerButton)] ? [gTabBarController centerButton] : nil;
    if ([button isKindOfClass:UIControl.class]) [button sendActionsForControlEvents:UIControlEventTouchUpInside];
}

// 等同于点首页顶栏原来的搜索。搜索页是从首页进的，不在首页时先切回去
static void openSearch(void) {
    UITab *home = pageTab(@"index");
    if (home && gTabBarController.selectedTab != home) gTabBarController.selectedTab = home;
    dispatch_async(dispatch_get_main_queue(), ^{
        [gSearchButton sendActionsForControlEvents:UIControlEventTouchUpInside];
    });
}

// 小红书把系统底栏刷成不透明的白底（换主题时还会再刷），页面因此被截在底栏上方。
// 它刷的时机很散，直接在底栏的这几个入口上拦，保持系统默认的悬浮样子
static BOOL isOurBar(UITabBar *bar) {
    return gTabBarController && bar == gTabBarController.tabBar;
}

%hook UITabBar

- (void)setStandardAppearance:(UITabBarAppearance *)appearance {
    %orig(isOurBar(self) ? [UITabBarAppearance new] : appearance);
}

- (void)setScrollEdgeAppearance:(UITabBarAppearance *)appearance {
    %orig(isOurBar(self) ? nil : appearance);
}

- (void)setBackgroundColor:(UIColor *)color {
    %orig(isOurBar(self) ? nil : color);
}

- (void)setBackgroundImage:(UIImage *)image {
    %orig(isOurBar(self) ? nil : image);
}

- (void)setTintColor:(UIColor *)color {
    %orig(isOurBar(self) ? UIColor.labelColor : color);
}

- (void)setTranslucent:(BOOL)translucent {
    %orig(translucent || isOurBar(self));
}

%end

// 小红书同步底栏时会把它认不出的标签项一律禁用，搜索那一格因此点不动
%hook UITabBarItem

- (void)setEnabled:(BOOL)enabled {
    %orig(enabled || (gSearchPage && self == gSearchPage.tabBarItem));
}

%end

%hook XYTabbarController

- (void)xy_suppressSystemTabBarContentIfNeeded {
}

- (BOOL)xy_shouldSkipSystemTabBarFrameAdjustment {
    return YES;
}

- (void)viewDidLoad {
    gTabBarController = self;
    %orig;
    self.tabBar.unselectedItemTintColor = UIColor.labelColor;
}

- (void)viewDidLayoutSubviews {
    %orig;
    UIView *legacy = [self customtabBar];
    if (legacy.alpha > 0 && pageTab(@"index")) legacy.alpha = 0;
    if (gTabsDirty && !self.isTabBarHidden) rebuildTabs();
}

- (void)setViewControllers:(NSArray<UIViewController *> *)pages animated:(BOOL)animated {
    gPages = nil;
    %orig;
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (UIViewController *page in pages) {
        UITabBarItem *item = page.tabBarItem;
        NSString *name = [item respondsToSelector:NSSelectorFromString(@"itemName")] ? [item valueForKey:@"itemName"] : nil;
        [names addObject:name ?: @""];
    }
    gPageNames = names;
    gPages = [pages copy];
    rebuildTabs();
}

// 小红书到处按「第几个页面」来操作，标签换了顺序、多了搜索之后，这几处要按它原来的顺序回答。
// 系统自己也会调这几个方法，那边要的是真实的显示顺序，所以只对来自小红书主程序的调用做换算

- (NSArray<UIViewController *> *)viewControllers {
    return (gPages && !gRebuilding && calledFromApp(__builtin_return_address(0))) ? gPages : %orig;
}

- (NSUInteger)selectedIndex {
    if (!gPages || gRebuilding || !calledFromApp(__builtin_return_address(0))) return %orig;
    UIViewController *page = self.selectedViewController;
    NSUInteger index = page ? [gPages indexOfObjectIdenticalTo:page] : NSNotFound;
    return index == NSNotFound ? 0 : index;
}

- (void)setSelectedIndex:(NSUInteger)index {
    if (!gPages || index >= gPages.count || !calledFromApp(__builtin_return_address(0))) return %orig;
    UITab *tab = pageTab(gPageNames[index]);
    if (tab) self.selectedTab = tab;  // 找不到说明这个标签被用户藏了
}

- (void)setSelectedViewController:(UIViewController *)page {
    NSUInteger index = gPages ? [gPages indexOfObjectIdenticalTo:page] : NSNotFound;
    if (index != NSNotFound && !gRebuilding && !pageTab(gPageNames[index])) return;
    %orig;
}

// 角标的下标是按它自己那条底栏算的，中间还夹着加号，所以按名字找回对应的标签
- (void)setBadgeValue:(id)value forItemAtIndex:(NSInteger)index {
    %orig;
    NSArray *legacy = [[self customtabBar] valueForKey:@"tabs"];
    if (index < 0 || index >= (NSInteger)legacy.count) return;
    id item = legacy[index];
    NSString *name = [item respondsToSelector:NSSelectorFromString(@"itemName")] ? [item valueForKey:@"itemName"] : nil;
    UITab *tab = name ? pageTab(name) : nil;
    tab.badgeValue = ([value isKindOfClass:NSString.class] && [value length]) ? value : nil;
}

- (void)setCustomTabBarHidden:(BOOL)hidden animated:(BOOL)animated {
    %orig;
    [self setTabBarHidden:hidden animated:animated];
}

%end

%hook XYPHHomeTabbarController

%new
- (BOOL)tabBarController:(UITabBarController *)controller shouldSelectTab:(UITab *)tab {
    if ([tab isKindOfClass:UISearchTab.class]) {
        openSearch();
        return NO;
    }
    if (![self respondsToSelector:@selector(tabBarController:shouldSelectViewController:)]) return YES;
    return [self tabBarController:controller shouldSelectViewController:tab.viewController];
}

%new
- (void)tabBarController:(UITabBarController *)controller didSelectTab:(UITab *)tab previousTab:(UITab *)previous {
    if ([self respondsToSelector:@selector(tabBarController:didSelectViewController:)])
        [self tabBarController:controller didSelectViewController:tab.viewController];
}

%end

// 二级页面大多不设 hidesBottomBarWhenPushed（旧底栏是它自己手动藏的），系统底栏会一直浮在上面
%hook XYPHNavigationViewController

- (void)pushViewController:(UIViewController *)page animated:(BOOL)animated {
    if (self.viewControllers.count) page.hidesBottomBarWhenPushed = YES;
    %orig;
}

- (void)setViewControllers:(NSArray<UIViewController *> *)pages animated:(BOOL)animated {
    for (NSUInteger i = 1; i < pages.count; i++) pages[i].hidesBottomBarWhenPushed = YES;
    %orig;
}

%end

// 官方给折叠屏写的那几处玻璃适配（搜索框、消息页导航栏等）顺带打开
%hook XYLiquidGlass

- (BOOL)enable {
    return YES;
}

%end

%hook XYDeviceUtility

+ (BOOL)useLiquidGlass {
    return YES;
}

%end

#pragma mark - 首页顶栏

// 内容延伸到顶栏后面，用系统的 soft 滚动边缘；右上角的搜索进了底栏，位置换成发布。
// 下沉布局是小红书给折叠屏写好的，这里让普通机型也用上。

static __weak UIView *gHomeBar;
static char kBarEdgeKey, kSoftEdgeKey, kPublishKey, kSegmentGlassKey;

static NSHashTable *pinnedEdgeEffects(void) {
    static NSHashTable *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ table = [NSHashTable weakObjectsHashTable]; });
    return table;
}

static void useSoftTopEdge(UIScrollView *list) {
    if (objc_getAssociatedObject(list, &kSoftEdgeKey)) return;
    objc_setAssociatedObject(list, &kSoftEdgeKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [pinnedEdgeEffects() addObject:list.topEdgeEffect];
    list.topEdgeEffect.style = UIScrollEdgeEffectStyle.softStyle;
    list.topEdgeEffect.hidden = NO;
}

// 这个列表是不是当前屏幕上、压在顶栏下面的那个竖向列表
static BOOL isListUnderBar(UIScrollView *list, UIView *bar) {
    if (list.hidden || !list.window || list.window != bar.window) return NO;
    if (list.contentSize.width > CGRectGetWidth(list.bounds) + 1 && list.pagingEnabled) return NO;
    if (list.contentSize.height <= CGRectGetHeight(list.bounds) && !list.alwaysBounceVertical) return NO;
    CGRect frame = [list convertRect:list.bounds toView:nil], barFrame = [bar convertRect:bar.bounds toView:nil];
    if (CGRectGetWidth(CGRectIntersection(frame, list.window.bounds)) < CGRectGetWidth(list.window.bounds) / 2) return NO;  // 在左右相邻的页里
    return CGRectGetMinY(frame) < CGRectGetMaxY(barFrame) - 1 && CGRectGetHeight(frame) > CGRectGetHeight(barFrame) * 2;
}

// 告诉系统顶栏压在这个列表上，边缘效果才会按顶栏的高度铺开。同一时刻只跟当前在看的那个列表
static void attachHomeBar(UIScrollView *list) {
    UIView *bar = gHomeBar;
    if (!bar || !isListUnderBar(list, bar)) return;
    useSoftTopEdge(list);
    UIScrollEdgeElementContainerInteraction *interaction = objc_getAssociatedObject(bar, &kBarEdgeKey);
    if (!interaction) {
        interaction = [UIScrollEdgeElementContainerInteraction new];
        interaction.edge = UIRectEdgeTop;
        [bar addInteraction:interaction];
        objc_setAssociatedObject(bar, &kBarEdgeKey, interaction, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (interaction.scrollView != list) interaction.scrollView = list;
}

static void findListUnderBar(UIView *root, UIView *bar, UIScrollView **best) {
    if ([root isKindOfClass:UIScrollView.class] && isListUnderBar((UIScrollView *)root, bar) &&
        (!*best || CGRectGetHeight(root.bounds) > CGRectGetHeight((*best).bounds)))
        *best = (UIScrollView *)root;
    for (UIView *view in root.subviews) findListUnderBar(view, bar, best);
}

// 左右切到别的页（关注 / 发现 / 同城）之后，把边缘效果接到新出现的那个列表上
static void attachVisibleList(void) {
    UIView *bar = gHomeBar;
    if (!bar.window) return;
    UIScrollView *list = nil;
    findListUnderBar(bar.superview, bar, &list);
    if (list) attachHomeBar(list);
}

// 主题图、分隔线和通栏磨砂各是一层，主题图的高度会按图片比例变化。
static void stripBarBackground(XYMHomeNaviBar *bar) {
    clearBackground(bar);
    UIView *theme = [bar respondsToSelector:@selector(background)] ? bar.background : nil;
    for (UIView *view in bar.subviews) {
        if (view.alpha == 0) continue;
        BOOL fullWidth = CGRectGetWidth(bar.bounds) > 0 &&
                         fabs(CGRectGetMinX(view.frame) - CGRectGetMinX(bar.bounds)) < 1 &&
                         fabs(CGRectGetWidth(view.frame) - CGRectGetWidth(bar.bounds)) < 1;
        BOOL backdrop = fullWidth && view.subviews.count <= 2 &&
            ([view isMemberOfClass:UIVisualEffectView.class] ||
             ([view isMemberOfClass:UIView.class] && (!view.userInteractionEnabled || CGRectEqualToRect(view.frame, bar.bounds))));
        if (view == theme || backdrop || (fullWidth && [view isKindOfClass:%c(_XYSeparatorView)])) view.alpha = 0;
    }
}

%hook XYMHomeViewController

- (BOOL)homeLiquidGlassEnabled {
    return YES;
}

%end

%hook XYMHomeLayoutAdapter

+ (id)adapterForCurrentDeviceUsingLiquidGlass:(BOOL)glass {
    Class duo = objc_getClass("_TtC12XYHomeModuleP33_C150DC52649AA0F032812B635DA9765C23XYMHomeDuoLayoutAdapter");
    return (glass && duo) ? [[duo alloc] init] : %orig;
}

%end

%hook XYEXLiquidGlassNavigationAdapter

// 小红书自带的磨砂底，不要
- (UIView *)frostedBackgroundView {
    UIView *view = %orig;
    if (view.alpha != 0) view.alpha = 0;
    return view;
}

// 下沉布局接管每个列表的入口
+ (void)layoutScrollView:(UIScrollView *)list inPage:(id)page {
    %orig;
    if (![list isKindOfClass:UIScrollView.class] || objc_getAssociatedObject(list, &kSoftEdgeKey)) return;
    useSoftTopEdge(list);
    dispatch_async(dispatch_get_main_queue(), ^{ attachVisibleList(); });
}

%end

// 下沉布局会把列表自己的顶部边缘效果关掉（因为它本来有磨砂底），这里保持打开
%hook UIScrollEdgeEffect

- (void)setHidden:(BOOL)hidden {
    %orig(hidden && ![pinnedEdgeEffects() containsObject:self]);
}

%end

%hook XYMHomeNaviBar

- (void)homeThemeChanged {
    %orig;
    stripBarBackground(self);
}

- (void)setIndex:(NSInteger)index {
    %orig;
    stripBarBackground(self);
    attachVisibleList();
    // 翻页动画结束后列表才完全到位，再接一次
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ attachVisibleList(); });
}

- (void)layoutSubviews {
    %orig;
    gHomeBar = self;
    stripBarBackground(self);

    UIButton *publish = objc_getAssociatedObject(self, &kPublishKey);
    UIView *menu = nil, *segment = nil, *search = nil;
    for (UIView *view in self.subviews) {
        NSString *name = NSStringFromClass(view.class);
        if ([name isEqualToString:@"XYMenuButton"]) menu = view;
        else if ([name isEqualToString:@"XYSegmentControl"]) segment = view;
        else if (view != publish && [view isKindOfClass:UIButton.class] && (!search || CGRectGetMinX(view.frame) > CGRectGetMinX(search.frame))) search = view;
    }
    if (!menu || !search) return;
    gSearchButton = (UIControl *)search;

    if (!publish) {
        UIButtonConfiguration *config = [UIButtonConfiguration glassButtonConfiguration];
        config.image = [UIImage systemImageNamed:@"plus"];
        config.preferredSymbolConfigurationForImage = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium];
        config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
        config.baseForegroundColor = UIColor.labelColor;
        publish = [UIButton buttonWithConfiguration:config primaryAction:[UIAction actionWithHandler:^(UIAction *action) { openPublish(); }]];
        publish.accessibilityLabel = @"发布";
        objc_setAssociatedObject(self, &kPublishKey, publish, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (publish.superview != self) [self addSubview:publish];
    if (!CGRectEqualToRect(publish.frame, search.frame)) publish.frame = search.frame;
    // 原搜索按钮和它背后那块玻璃都收起来（玻璃是和按钮同一位置的另一个视图）
    for (UIView *view in self.subviews) {
        BOOL backing = [view isKindOfClass:UIVisualEffectView.class] && CGRectEqualToRect(view.frame, search.frame);
        if ((view == search || backing) && !view.hidden) view.hidden = YES;
    }

    if (!segment) return;
    // 「关注 发现 同城」垫一块玻璃，文字压在图片上才看得清；高度和两侧按钮对齐，在两个按钮之间居中
    CGFloat left = CGRectGetMaxX(menu.frame) + 8, right = CGRectGetMinX(publish.frame) - 8;
    CGFloat width = MIN(right - left, CGRectGetWidth(segment.frame) + 16);
    CGFloat x = left + (right - left - width) / 2;
    CGRect frame = segment.frame;
    frame.origin.x = x + (width - CGRectGetWidth(frame)) / 2;
    if (!CGRectEqualToRect(segment.frame, frame)) segment.frame = frame;
    plate(self, &kSegmentGlassKey, segment, segment.hidden ? CGRectZero : CGRectMake(x, CGRectGetMinY(menu.frame), width, CGRectGetHeight(menu.frame)), kBarHome);
}

%end

#pragma mark - 滚动联动

// 小红书的页面是多层嵌套的分页容器，系统找不到真正在滚的那个列表。
// 手指开始拖的时候把它登记成当前页面的内容滚动视图，系统的「滚动收起底栏」才会生效。

@interface XHSNativeScrollTracker : NSObject
@end

@implementation XHSNativeScrollTracker

+ (instancetype)shared {
    static XHSNativeScrollTracker *tracker;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ tracker = [XHSNativeScrollTracker new]; });
    return tracker;
}

- (void)pan:(UIPanGestureRecognizer *)pan {
    UIScrollView *list = (UIScrollView *)pan.view;
    if (pan.state != UIGestureRecognizerStateBegan || ![list isKindOfClass:UIScrollView.class]) return;
    // 只认竖向列表，横向分页容器不算
    if (list.contentSize.height <= CGRectGetHeight(list.bounds) && !list.alwaysBounceVertical) return;
    if (list.contentSize.width > CGRectGetWidth(list.bounds) + 1 && list.pagingEnabled) return;

    UINavigationController *navigation = (UINavigationController *)gTabBarController.selectedViewController;
    UIViewController *page = [navigation isKindOfClass:UINavigationController.class] ? navigation.topViewController : navigation;
    if (!page.isViewLoaded || ![list isDescendantOfView:page.view]) return;
    attachHomeBar(list);
    if ([page contentScrollViewForEdge:NSDirectionalRectEdgeBottom] != list) [page setContentScrollView:list forEdge:NSDirectionalRectEdgeBottom];
}

@end

static void trackScrollView(UIScrollView *list) {
    static char key;
    if (!list.window || objc_getAssociatedObject(list, &key)) return;
    objc_setAssociatedObject(list, &key, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [list.panGestureRecognizer addTarget:[XHSNativeScrollTracker shared] action:@selector(pan:)];
}

// UICollectionView / UITableView 各自重写了 didMoveToWindow，不一定走到 UIScrollView 的实现，三个都挂
%hook UIScrollView
- (void)didMoveToWindow {
    %orig;
    trackScrollView(self);
}
%end

%hook UICollectionView
- (void)didMoveToWindow {
    %orig;
    trackScrollView(self);
}
%end

%hook UITableView
- (void)didMoveToWindow {
    %orig;
    trackScrollView(self);
}
%end

#pragma mark - 市集 / 消息 / 我

// 换成悬浮的系统底栏后，这几页底下会空出一条。原因有两种：
// 页面按旧底栏的高度（44 + 底部安全区）把内容区截短了（市集），或者页面不肯延伸到栏下面（消息）。

static BOOL nearlyEqual(CGFloat a, CGFloat b) {
    return fabs(a - b) < 1.5;
}

// 把一个「底边正好停在旧底栏上沿」的视图往下加长 gap
static BOOL growView(UIView *view, CGFloat gap) {
    for (NSLayoutConstraint *constraint in view.constraints) {
        if (constraint.firstItem == view && !constraint.secondItem && constraint.firstAttribute == NSLayoutAttributeHeight &&
            constraint.relation == NSLayoutRelationEqual && constraint.isActive && nearlyEqual(constraint.constant, CGRectGetHeight(view.bounds))) {
            constraint.constant += gap;
            return YES;
        }
    }
    for (NSLayoutConstraint *constraint in view.superview.constraints) {
        if (!constraint.isActive || constraint.relation != NSLayoutRelationEqual || constraint.multiplier != 1) continue;
        BOOL pinned = (constraint.firstItem == view && constraint.secondItem == view.superview) || (constraint.firstItem == view.superview && constraint.secondItem == view);
        if (!pinned || constraint.firstAttribute != NSLayoutAttributeBottom || constraint.secondAttribute != NSLayoutAttributeBottom) continue;
        if (nearlyEqual(fabs(constraint.constant), gap)) {
            constraint.constant = 0;
            return YES;
        }
    }
    if (!view.translatesAutoresizingMaskIntoConstraints) return NO;
    CGRect frame = view.frame;
    frame.size.height += gap;
    view.frame = frame;
    return YES;
}

static void extendDown(UIView *parent, UIView *root, CGFloat gap, int depth) {
    CGFloat height = CGRectGetHeight(root.bounds), width = CGRectGetWidth(root.bounds);
    for (UIView *view in [parent.subviews copy]) {
        if (view.hidden || view.alpha < 0.01) continue;
        CGRect frame = [root convertRect:view.bounds fromView:view];
        if (CGRectGetWidth(frame) < width * 0.9 || CGRectGetHeight(frame) <= gap) continue;
        if (nearlyEqual(CGRectGetMaxY(frame), height - gap) && growView(view, gap)) {
            [view.superview layoutIfNeeded];
            frame = [root convertRect:view.bounds fromView:view];
        }
        if (CGRectGetMaxY(frame) < height - gap - 1.5) continue;  // 够不到底部那一段，里面不用看
        if ([view isKindOfClass:UIScrollView.class]) {
            UIScrollView *list = (UIScrollView *)view;
            if (list.contentSize.width <= CGRectGetWidth(list.bounds) + 1) {
                // 延伸到底的竖向列表，末尾留出底栏的位置；里面是单元格，不往里找
                if (nearlyEqual(CGRectGetMaxY(frame), height) && list.adjustedContentInset.bottom < gap) {
                    UIEdgeInsets inset = list.contentInset;
                    inset.bottom += gap - list.adjustedContentInset.bottom;
                    list.contentInset = inset;
                }
                continue;
            }
        }
        if (depth < 9) extendDown(view, root, gap, depth + 1);
    }
}

static void extendTabPage(UIViewController *page) {
    UINavigationController *navigation = page.navigationController;
    if (!page.view.window || navigation.viewControllers.firstObject != page || navigation.parentViewController != gTabBarController) return;
    if (!(page.edgesForExtendedLayout & UIRectEdgeBottom)) {
        page.edgesForExtendedLayout |= UIRectEdgeBottom;
        [navigation.view setNeedsLayout];
    }
    static BOOL busy;
    if (busy) return;
    busy = YES;
    extendDown(page.view, page.view, 44 + page.view.window.safeAreaInsets.bottom, 0);
    busy = NO;
}

%hook XYMarketRootInterface
- (void)viewDidLayoutSubviews {
    %orig;
    extendTabPage(self);
}
%end

%hook XYPMMessageCenterViewController
- (void)configureNavigationBarLiquidGlass {
    %orig;
    if (!prefBool(kGlassMessages, YES) || [self valueForKey:@"navigationGlassView"]) return;
    for (UIBarButtonItem *item in self.navigationItem.rightBarButtonItems)
        item.hidesSharedBackground = NO;
}
- (void)viewDidLayoutSubviews {
    %orig;
    extendTabPage(self);
}
%end

%hook XYPFProfileViewController
- (void)viewDidLayoutSubviews {
    %orig;
    extendTabPage(self);
}
%end

#pragma mark - 搜索页

%hook XYNativeSearchBar
- (void)didMoveToWindow {
    %orig;
    XYNativeSearchBar *bar = self;
    if (!bar.window || !prefBool(kGlassSearch, YES)) return;
    for (UIResponder *r = self; r; r = r.nextResponder) {
        if (![r isKindOfClass:%c(XYPHSearchNavigationViewController)]) continue;
        if (!bar.usesLiquidGlass) bar.usesLiquidGlass = YES;
        break;
    }
}
%end

#pragma mark - 个人页

%hook XYPFProfileV2NavigationBar
- (void)layoutSubviews {
    %orig;
    static char leftKey, rightKey;
    UIView *menu = [self homeMenuButton];
    BOOL enabled = prefBool(kGlassProfile, YES) && ![self usesDuoNavigation] && isVisible(menu) && menu.superview == self;
    if (enabled) plate(self, &leftKey, menu, CGRectInset(menu.frame, -6, -6), @"profile");
    else ((UIView *)objc_getAssociatedObject(self, &leftKey)).hidden = YES;

    CGRect group = CGRectNull;
    UIView *first = nil;
    if (enabled) {
        UIView *share = [self shareButton], *scan = [self scanButton], *edit = [self editButton];
        for (UIView *button in self.subviews) {
            if (button != share && button != scan && button != edit) continue;
            if (!isVisible(button)) continue;
            first = first ?: button;
            group = CGRectUnion(group, button.frame);
        }
    }
    if (first) plate(self, &rightKey, first, CGRectInset(group, -6, -6), @"profile");
    else ((UIView *)objc_getAssociatedObject(self, &rightKey)).hidden = YES;
}
%end

#pragma mark - 私聊输入栏

%hook XYChatBarLayout
- (BOOL)usesGlassAppearance {
    if (%orig) return YES;
    if (!prefBool(kGlassChat, YES)) return NO;
    for (UIViewController *page = [(UIViewController *)self parentViewController]; page; page = page.parentViewController) {
        if ([page isKindOfClass:%c(XYPMChatBaseViewController)]) return ![(XYPMChatBaseViewController *)page isFloating];
    }
    return NO;
}
%end

#pragma mark - 评论半屏

%hook XYCommentHalfBar
- (void)layoutSubviews {
    %orig;
    static char glassKey;
    for (UIView *input in [(UIView *)self subviews]) {
        if (![input isKindOfClass:objc_getClass("XYNoteBasic.CommentBarStaticViewV2024")]) continue;
        UIVisualEffectView *glass = objc_getAssociatedObject(input, &glassKey);
        if (!prefBool(kGlassComments, YES)) { glass.hidden = YES; return; }
        for (UIView *content in input.subviews) {
            if (content == glass) continue;
            plate(input, &glassKey, content, input.bounds, @"comment");
            return;
        }
    }
}
%end

#pragma mark - 图文笔记页

// 正文延伸到上下两条栏的后面，栏的底色去掉，控件悬浮在玻璃胶囊上。
// 顶栏两块：返回 + 头像 + 昵称 / 关注 + 分享；底栏一块：评论框 + 点赞收藏评论。

static char kNoteLeftKey, kNoteRightKey, kNoteBottomKey, kNoteEdgeKey;

static UIView *subviewOfClass(UIView *view, NSString *className) {
    for (UIView *subview in view.subviews)
        if ([NSStringFromClass(subview.class) isEqualToString:className]) return subview;
    return nil;
}

static void layoutNoteTop(UIView *bar) {
    clearBackground(bar);
    // 控件那一行在安全区下面
    UIView *row = nil;
    for (UIView *view in bar.subviews) {
        if ([view isKindOfClass:UIVisualEffectView.class] || view.hidden || CGRectGetHeight(view.frame) <= 30) continue;
        if (!row || CGRectGetMinY(view.frame) > CGRectGetMinY(row.frame)) row = view;
    }
    if (!row) return;
    clearBackground(row);

    UIView *back = nil, *author = nil;
    for (UIView *view in row.subviews) {
        if ([view isKindOfClass:UIButton.class]) back = back ?: view;
        else author = subviewOfClass(view, @"XYNoteModule.NoteDirectionView") ?: author;
    }
    if (!author) return;
    UIView *avatar = nil, *follow = nil, *share = nil, *name = nil;
    for (UIView *view in author.subviews) {
        if ([view isKindOfClass:objc_getClass("XYFollowBtn")]) follow = view;
        else if ([view isKindOfClass:UIButton.class]) share = view;
        else if ([view isKindOfClass:UIStackView.class]) name = name ?: view;
        else if ([NSStringFromClass(view.class) isEqualToString:@"XYUserAvatar"]) avatar = view;
    }

    CGFloat y = CGRectGetMidY(row.frame) - 24;
    // 右边：关注 + 分享
    UIView *first = isVisible(follow) ? follow : (isVisible(share) ? share : nil);
    CGRect right = CGRectZero;
    if (first) {
        CGFloat x = CGRectGetMinX([bar convertRect:first.bounds fromView:first]) - (first == follow ? 6 : 12);
        right = CGRectMake(x, y, CGRectGetWidth(bar.bounds) - 8 - x, 48);
    }
    // 左边：返回 + 头像 + 昵称，按内容收窄
    UIView *last = isVisible(name) ? name : (isVisible(avatar) ? avatar : back);
    CGFloat maxX = CGRectGetMaxX([bar convertRect:last.bounds fromView:last]) + (last == back ? 12 : 16);
    if (first) maxX = MIN(maxX, CGRectGetMinX(right) - 8);
    plate(bar, &kNoteLeftKey, row, CGRectMake(8, y, maxX - 8, 48), kBarNoteTop);
    plate(bar, &kNoteRightKey, row, right, kBarNoteTop);
}

static void layoutNoteBottom(UIView *bar) {
    clearBackground(bar);
    XYNoteInteractionView *content = (id)subviewOfClass(bar, @"XYNoteModule.InteractionView");
    if (!content) return;
    clearBackground(content);
    UIView *stack = nil;
    for (UIView *view in content.subviews) {
        if ([view isKindOfClass:UIVisualEffectView.class]) continue;
        if ([view isKindOfClass:UIStackView.class]) stack = stack ?: view;
        // 顶上那条分隔线：不到 1pt 高，里面没东西
        else if (!view.subviews.count && CGRectGetHeight(view.frame) > 0 && CGRectGetHeight(view.frame) <= 1 && !view.hidden) view.hidden = YES;
    }
    if (CGRectGetHeight(stack.frame) <= 1) return;
    // 点赞动画单独绘制，图标上原本有一块与页面同色的方形遮底。
    XYLottieAnimationButton *like = [content respondsToSelector:@selector(likeButton)] ? content.likeButton : nil;
    UIView *mask = [like respondsToSelector:@selector(lottieMaskView)] ? like.lottieMaskView : nil;
    if (mask && mask.superview == like.imageView && !mask.subviews.count && mask.alpha != 0) mask.alpha = 0;
    // 评论框自带的灰色药丸底去掉，和旁边的按钮一样直接放在玻璃上
    for (UIView *group in stack.subviews)
        for (UIView *field in group.subviews)
            if ([NSStringFromClass(field.class) hasSuffix:@"Field"]) clearBackground(field);
    plate(bar, &kNoteBottomKey, stack, CGRectMake(8, CGRectGetMidY(stack.frame) - 24, CGRectGetWidth(content.bounds) - 16, 48), kBarNoteBottom);
}

static void layoutNotePage(UIViewController *page) {
    if (!prefBool(kGlassNote, YES)) return;
    UIView *root = page.view;
    UIView *top = subviewOfClass(root, @"XYNoteModule.NavigationBar"), *bottom = subviewOfClass(root, @"XYNoteModule.NoteDetailBottomView");
    UICollectionView *list = nil;
    for (UIView *view in root.subviews)
        if ([view isKindOfClass:UICollectionView.class]) list = list ?: (UICollectionView *)view;
    if (!top || !bottom || !list || top.hidden || bottom.hidden) return;

    // 首图沿用导航栏下沿作为起点。滚出列表边界的部分可以透过导航栏看到。
    CGFloat start = CGRectGetMaxY(top.frame);
    CGRect viewport = CGRectMake(0, start, CGRectGetWidth(root.bounds), CGRectGetHeight(root.bounds) - start);
    if (CGRectIsEmpty(viewport)) return;
    UIEdgeInsets extra = page.additionalSafeAreaInsets;
    extra.bottom = MAX(0, CGRectGetMaxY(root.bounds) - CGRectGetMinY(bottom.frame) - root.window.safeAreaInsets.bottom);
    if (!UIEdgeInsetsEqualToEdgeInsets(page.additionalSafeAreaInsets, extra)) page.additionalSafeAreaInsets = extra;
    if (!CGRectEqualToRect(list.frame, viewport)) list.frame = viewport;
    if (list.clipsToBounds) list.clipsToBounds = NO;
    if (list.contentInsetAdjustmentBehavior != UIScrollViewContentInsetAdjustmentAlways)
        list.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAlways;

    // 顶部用系统的 soft 边缘；底部不要边缘效果，胶囊直接浮在正文上
    list.topEdgeEffect.style = UIScrollEdgeEffectStyle.softStyle;
    if (!list.bottomEdgeEffect.hidden) list.bottomEdgeEffect.hidden = YES;
    UIScrollEdgeElementContainerInteraction *interaction = objc_getAssociatedObject(top, &kNoteEdgeKey);
    if (!interaction) {
        interaction = [UIScrollEdgeElementContainerInteraction new];
        interaction.edge = UIRectEdgeTop;
        [top addInteraction:interaction];
        objc_setAssociatedObject(top, &kNoteEdgeKey, interaction, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (interaction.scrollView != list) interaction.scrollView = list;

    layoutNoteTop(top);
    layoutNoteBottom(bottom);
}

// 「头像 昵称 关注 分享」这一条是贴着安全区摆的，上面把栏高记进安全区之后它会被推到栏外，
// 用位移把它放回容器的垂直正中（位移不参与自动布局，不会和它的约束打架）
static void recenterAuthorRow(UIView *row) {
    if (!prefBool(kGlassNote, YES)) return;
    UIView *box = row.superview;
    CGFloat y = row.center.y - CGRectGetHeight(row.bounds) / 2;
    CGFloat offset = (CGRectGetHeight(box.bounds) - CGRectGetHeight(row.bounds)) / 2 - y;
    CGAffineTransform transform = fabs(offset) < 0.5 ? CGAffineTransformIdentity : CGAffineTransformMakeTranslation(0, offset);
    if (!CGAffineTransformEqualToTransform(row.transform, transform)) row.transform = transform;
    // 昵称是异步填进来的，宽度变了胶囊要跟着改
    for (UIView *view = box; view; view = view.superview) {
        if (![NSStringFromClass(view.class) isEqualToString:@"XYNoteModule.NavigationBar"]) continue;
        layoutNoteTop(view);
        break;
    }
}

%hook XYNoteDetailPage
- (void)viewDidLayoutSubviews {
    %orig;
    layoutNotePage(self);
}
%end

%hook XYNoteDirectionView
- (void)layoutSubviews {
    %orig;
    recenterAuthorRow(self);
}
%end

// 关注按钮原来是红色描边的小药丸，放进玻璃里显得碎。去掉描边只留字，字稍微加重
%hook XYFollowBtn

- (void)layoutSubviews {
    %orig;
    if (!prefBool(kGlassNote, YES) || ![NSStringFromClass(self.superview.class) isEqualToString:@"XYNoteModule.NoteDirectionView"]) return;
    if (self.layer.borderWidth != 0) self.layer.borderWidth = 0;
    clearBackground(self);
    UIFont *font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    if (![self.titleLabel.font isEqual:font]) self.titleLabel.font = font;
}

%end

#pragma mark - 视频页

// 顶上的按钮按左右分成两个胶囊（返回 + 小窗 / 搜索 + 分享），底部互动栏垫一个胶囊。
// 视频页永远是深色界面，玻璃固定用深色。

static char kVideoLeftKey, kVideoRightKey, kVideoBottomKey;

static void darken(UIVisualEffectView *glass) {
    if (glass.overrideUserInterfaceStyle != UIUserInterfaceStyleDark) glass.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
}

static void layoutVideoHead(UIView *head) {
    if (!prefBool(kGlassVideo, YES)) return;
    CGFloat middle = CGRectGetMidX(head.bounds);
    CGRect left = CGRectNull, right = CGRectNull;
    UIView *lowest = nil;
    for (UIView *view in head.subviews) {
        if ([view isKindOfClass:UIVisualEffectView.class]) continue;
        lowest = lowest ?: view;
        if (![view isKindOfClass:UIControl.class] || !isVisible(view)) continue;
        if (CGRectGetMidX(view.frame) < middle) left = CGRectUnion(left, view.frame);
        else right = CGRectUnion(right, view.frame);
    }
    if (!lowest) return;
    CGRect (^around)(CGRect) = ^CGRect(CGRect buttons) {
        return CGRectIsNull(buttons) ? CGRectZero : CGRectMake(CGRectGetMinX(buttons) - 9, CGRectGetMidY(buttons) - 22, CGRectGetWidth(buttons) + 18, 44);
    };
    darken(plate(head, &kVideoLeftKey, lowest, around(left), kBarVideoTop));
    darken(plate(head, &kVideoRightKey, lowest, around(right), kBarVideoTop));
}

static void layoutVideoEngage(UIView *bar) {
    if (!prefBool(kGlassVideo, YES)) return;
    CGRect row = CGRectNull;
    UIView *lowest = nil;
    for (UIView *view in bar.subviews) {
        if ([view isKindOfClass:UIVisualEffectView.class]) continue;
        lowest = lowest ?: view;
        if (!isVisible(view)) continue;
        row = CGRectUnion(row, view.frame);
        // 评论框自带的灰色药丸底去掉
        if ([NSStringFromClass(view.class) hasSuffix:@"VFBottomWriteCmtView"])
            for (UIView *field in view.subviews) clearBackground(field);
    }
    if (!lowest || CGRectIsNull(row)) return;
    // 这一排控件的可见内容在各自格子的下半部分
    darken(plate(bar, &kVideoBottomKey, lowest, CGRectMake(8, CGRectGetMaxY(row) - 39, CGRectGetWidth(bar.bounds) - 16, 44), kBarVideoBottom));
}

%hook XYVFHeadView
- (void)layoutSubviews {
    %orig;
    layoutVideoHead(self);
}
%end

%hook XYVFBottomEngageView
- (void)layoutSubviews {
    %orig;
    layoutVideoEngage(self);
}
%end

#pragma mark - 设置界面

// 用小红书自己的设置组件搭：页面是 XYSettingBaseViewController，行是 StandardOption，
// 写法和它的「深色模式」页一样，所以样子、开关、返回都是它原生的。入口是它「设置」页的第一行。
// 它这套组件的属性都是返回 block 的链式写法，下面几个小函数把调用包一下

static id blockOf(id target, NSString *name) {
    return ((id (*)(id, SEL))objc_msgSend)(target, NSSelectorFromString(name));
}

static id rowTitle(NSString *text) {
    id (^make)(NSString *) = blockOf(objc_getClass("StandardOptionTitle"), @"title");
    return make(text);
}

static id with(id object, NSString *name, id value) {
    id (^apply)(id) = blockOf(object, name);
    return apply(value);
}

static id withFlag(id object, NSString *name, BOOL value) {
    id (^apply)(BOOL) = blockOf(object, name);
    return apply(value);
}

static id row(NSString *kind, id title, NSString *identity) {
    id (^make)(id) = blockOf(objc_getClass("StandardOption"), kind);
    return with(make(title), @"setIdentity", identity);
}

static id gap(CGFloat height) {
    id (^make)(double) = blockOf(objc_getClass("StandardOption"), @"blank");
    return make(height);
}

static NSString *const kEntryIdentity = @"XHSNative";

static void applySettings(void) {
    rebuildTabs();
    [gHomeBar setNeedsLayout];
}

static NSDictionary<NSString *, NSString *> *tabNames(void) {
    return @{@"index": @"首页", @"shopping": @"市集", @"message": @"消息", @"me": @"我"};
}

static NSArray<NSArray *> *glassBars(void) {
    return @[@[@"首页顶栏", kBarHome], @[@"笔记顶栏", kBarNoteTop], @[@"笔记底栏", kBarNoteBottom], @[@"视频顶栏", kBarVideoTop], @[@"视频底栏", kBarVideoBottom], @[@"评论输入栏", @"comment"], @[@"个人页顶栏", @"profile"]];
}

static id switchRow(NSString *title, BOOL on, NSString *identity) {
    id text = withFlag(rowTitle(title), @"setSwitcherIsOn", on);
    return row(@"switcher", text, identity);
}

static UIView *settingsFooter(CGFloat width) {
    UIStackView *footer = [UIStackView new];
    footer.axis = UILayoutConstraintAxisVertical;
    footer.alignment = UIStackViewAlignmentCenter;
    footer.spacing = 8;
    footer.layoutMarginsRelativeArrangement = YES;
    footer.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(14, 0, 14, 0);

    UIFont *font = [UIFont systemFontOfSize:12];
    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    NSInteger year = [calendar component:NSCalendarUnitYear fromDate:NSDate.date];
    NSString *copyright = [NSString stringWithFormat:@"© %ld huamidev. All rights reserved.", (long)year];
    NSArray *lines = @[@"XHSNative", @"Version: " XHSNativeVersion, @"Developed by huami1314", copyright];
    CGFloat opacity[] = {0.8, 0.56, 0.56 * 0.7, 0.56 * 0.5};
    for (NSUInteger i = 0; i < lines.count; i++) {
        UILabel *label = [UILabel new];
        label.text = lines[i];
        label.font = font;
        label.textAlignment = NSTextAlignmentCenter;
        label.textColor = [UIColor.labelColor colorWithAlphaComponent:opacity[i]];
        [footer addArrangedSubview:label];
    }
    CGFloat height = [footer systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].height;
    footer.frame = CGRectMake(0, 0, width, ceil(height));
    return footer;
}

static NSArray *settingsRows(void) {
    NSMutableArray *rows = [NSMutableArray arrayWithObject:gap(12)];
    [rows addObject:row(@"label", rowTitle(@"底部标签栏"), @"tabs.heading")];
    [rows addObject:gap(8)];
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    for (NSString *name in tabOrder()) [order addObject:tabNames()[name]];
    [rows addObject:row(@"arrow", with(rowTitle(@"标签顺序"), @"setTrailing", [order componentsJoinedByString:@" "]), @"order")];
    for (NSString *name in @[@"shopping", @"message", @"me"])
        [rows addObject:switchRow(tabNames()[name], !tabHidden(name), [@"tab." stringByAppendingString:name])];
    [rows addObject:switchRow(@"搜索", prefBool(kSearchTab, YES), [@"pref." stringByAppendingString:kSearchTab])];
    [rows addObject:switchRow(@"滚动时收起", prefBool(kMinimize, YES), [@"pref." stringByAppendingString:kMinimize])];
    [rows addObject:gap(24)];

    [rows addObject:row(@"label", rowTitle(@"液态玻璃"), @"glass.heading")];
    [rows addObject:gap(8)];
    for (NSArray *option in @[@[@"图文笔记", kGlassNote], @[@"视频", kGlassVideo], @[@"搜索栏", kGlassSearch],
                              @[@"评论输入栏", kGlassComments], @[@"私聊输入栏", kGlassChat],
                              @[@"消息顶栏", kGlassMessages], @[@"个人页顶栏", kGlassProfile]])
        [rows addObject:switchRow(option[0], prefBool(option[1], YES), [@"pref." stringByAppendingString:option[1]])];
    [rows addObject:gap(8)];
    [rows addObject:row(@"label", rowTitle(@"下次进入页面时生效。"), @"glass.note")];
    [rows addObject:gap(24)];

    [rows addObject:row(@"label", rowTitle(@"不透明度"), @"fillHeading")];
    [rows addObject:gap(8)];
    for (NSArray *bar in glassBars()) {
        id title = with(rowTitle(bar[0]), @"setTrailing", [NSString stringWithFormat:@"%.0f%%", fillOf(bar[1])]);
        [rows addObject:row(@"arrow", title, [@"fill." stringByAppendingString:bar[1]])];
    }
    [rows addObject:gap(24)];
    [rows addObject:row(@"button", rowTitle(@"恢复默认"), @"reset")];
    return rows;
}

static NSArray *orderRows(void) {
    NSMutableArray *rows = [NSMutableArray array];
    for (NSString *name in tabOrder())
        [rows addObject:withFlag(row(@"text", rowTitle(tabNames()[name]), name), @"setCornerMaskUsesCellBounds", YES)];
    return rows;
}

// 选不透明度：0% 是纯玻璃，越大越不透
static NSArray *percentRows(NSString *bar) {
    NSMutableArray *rows = [NSMutableArray arrayWithObject:gap(12)];
    for (NSInteger percent = 0; percent <= 100; percent += 10) {
        id title = withFlag(rowTitle([NSString stringWithFormat:@"%ld%%", (long)percent]), @"setSelected", percent == (NSInteger)fillOf(bar));
        [rows addObject:row(@"selector", title, [NSString stringWithFormat:@"percent.%ld", (long)percent])];
    }
    [rows addObject:gap(8)];
    [rows addObject:row(@"label", rowTitle(@"0% 是纯玻璃，数值越大越不透。"), @"note")];
    return rows;
}

static void handleRowTap(XHSNativeSettingsPage *page, NSString *identity) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([identity isEqualToString:@"order"] || [identity hasPrefix:@"fill."]) {
        XHSNativeSettingsPage *next = [[%c(XHSNativeSettingsPage) alloc] init];
        next.mode = [identity hasPrefix:@"fill."] ? [identity substringFromIndex:5] : identity;
        [page.navigationController pushViewController:next animated:YES];
    } else if ([identity hasPrefix:@"percent."]) {
        [defaults setDouble:[identity substringFromIndex:8].doubleValue forKey:fillKey(page.mode)];
        applySettings();
        [page.navigationController popViewControllerAnimated:YES];
    } else if ([identity isEqualToString:@"reset"]) {
        for (NSString *key in defaults.dictionaryRepresentation.allKeys)
            if ([key hasPrefix:@"XHSNative."]) [defaults removeObjectForKey:key];
        applySettings();
        [page reloadRows];
    }
}

static void handleSwitch(NSString *identity, BOOL on) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([identity hasPrefix:@"pref."]) {
        [defaults setBool:on forKey:[identity substringFromIndex:5]];
    } else if ([identity hasPrefix:@"tab."]) {
        NSString *name = [identity substringFromIndex:4];
        NSMutableArray<NSString *> *hidden = [([defaults stringArrayForKey:kTabHidden] ?: @[]) mutableCopy];
        [hidden removeObject:name];
        if (!on) [hidden addObject:name];
        [defaults setObject:hidden forKey:kTabHidden];
    }
    applySettings();
}

%subclass XHSNativeSettingsPage : XYSettingBaseViewController

%property (nonatomic, strong) id model;
%property (nonatomic, copy) NSString *mode;

- (id)vm {
    XHSNativeSettingsPage *page = self;
    if (!page.model) page.model = [[objc_getClass("SettingViewModel") alloc] init];
    return page.model;
}

- (void)viewDidLoad {
    %orig;
    XHSNativeSettingsPage *page = self;
    NSString *title = @"XHSNative";
    if (!page.mode) page.tableView.tableFooterView = settingsFooter(CGRectGetWidth(page.tableView.bounds));
    if ([page.mode isEqualToString:@"order"]) {
        title = @"标签顺序";
        [page.tableView setEditing:YES animated:NO];
    }
    for (NSArray *bar in glassBars())
        if ([bar[1] isEqualToString:page.mode]) title = [bar[0] stringByAppendingString:@"不透明度"];
    [[page navBar] setValue:title forKey:@"title"];
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    [self reloadRows];
}

%new
- (BOOL)tableView:(UITableView *)table canMoveRowAtIndexPath:(NSIndexPath *)path {
    return [((XHSNativeSettingsPage *)self).mode isEqualToString:@"order"];
}

%new
- (UITableViewCellEditingStyle)tableView:(UITableView *)table editingStyleForRowAtIndexPath:(NSIndexPath *)path {
    return UITableViewCellEditingStyleNone;
}

%new
- (BOOL)tableView:(UITableView *)table shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)path {
    return NO;
}

%new
- (void)tableView:(UITableView *)table moveRowAtIndexPath:(NSIndexPath *)source toIndexPath:(NSIndexPath *)destination {
    if ([source isEqual:destination]) return;
    NSMutableArray *order = [tabOrder() mutableCopy];
    NSString *name = order[source.row];
    [order removeObjectAtIndex:source.row];
    [order insertObject:name atIndex:destination.row];
    [NSUserDefaults.standardUserDefaults setObject:order forKey:kTabOrder];
    [[(XHSNativeSettingsPage *)self vm] setValue:orderRows() forKey:@"options"];
    // 拖动结束后，按新位置重设首尾行的圆角。
    dispatch_async(dispatch_get_main_queue(), ^{ [table reloadData]; });
    applySettings();
}

%new
- (void)reloadRows {
    XHSNativeSettingsPage *page = self;
    NSArray *rows = !page.mode ? settingsRows() : ([page.mode isEqualToString:@"order"] ? orderRows() : percentRows(page.mode));
    ((void (*)(id, SEL, id))objc_msgSend)([page vm], NSSelectorFromString(@"reload:"), rows);
}

- (void)didSelectOption:(id)option {
    handleRowTap(self, [option valueForKey:@"identity"]);
}

// 开关拨动。两个参数一个是这一行的选项，一个是带开关的单元格
- (void)didChangeValueFor:(id)first related:(id)second {
    id option = [first respondsToSelector:NSSelectorFromString(@"identity")] ? first : second;
    id cell = option == first ? second : first;
    handleSwitch([option valueForKey:@"identity"], [[cell valueForKey:@"isOn"] boolValue]);
}

%end

// 入口：往它「设置」页的数据里插一行，排在最前面，自成一组
%hook XYPHSettingTableViewModel

- (void)setOptions:(NSArray *)options {
    if (options.count) {
        id entry = row(@"leftIconArrow", with(rowTitle(@"XHSNative"), @"setIconFont", themeGlyph(@"filters_b")), kEntryIdentity);
        NSMutableArray *rows = [options mutableCopy];
        [rows insertObject:[self blank] atIndex:1];
        [rows insertObject:entry atIndex:1];
        options = rows;
    }
    %orig;
}

%end

%hook XYPHSettingViewController

- (void)didSelectOption:(id)option {
    if (![[option valueForKey:@"identity"] isEqual:kEntryIdentity]) return %orig;
    [self.navigationController pushViewController:[[%c(XHSNativeSettingsPage) alloc] init] animated:YES];
}

%end

#pragma mark - iOS 27.1 以下

// 首页的下沉布局是按 iOS 27.1 写的，用到三个更早的系统上没有的东西：
// 特征 verticalBarEdge，Swift 的 UITraitCollection.systemTraitsAffectingVerticalBarEdge
// 和 UIView.LayoutRegion.bar(onEdge:extent:)。
// 第一个补一个返回「未指定」的方法。后两个在导入表里是空的，一调就崩：
// 一个填上返回空数组的函数（没有竖排栏，也就没有要监听的特征），
// 一个填上转给 safeArea 的跳板（没有竖排栏时这个区域的上边界就是安全区，结果一样）。

static NSInteger verticalBarEdgeUnspecified(id self, SEL _cmd) {
    return 0;
}

// 跳板的目标和参数。参数是 AdaptivityAxis?，这个枚举跨模块按地址传，nil 是字节 2
__attribute__((used, visibility("hidden"))) void *gSafeAreaRegion;
__attribute__((used, visibility("hidden"))) uint64_t gNoAxis = 2;

__attribute__((naked)) static void layoutRegionBar(void) {
    __asm__ volatile("adrp x16, _gSafeAreaRegion@PAGE\n"
                     "ldr x16, [x16, _gSafeAreaRegion@PAGEOFF]\n"
                     "adrp x0, _gNoAxis@PAGE\n"
                     "add x0, x0, _gNoAxis@PAGEOFF\n"
                     "br x16\n");
}

// 在主程序的导入表里按符号名找到对应的指针槽：间接符号表 → 符号表 → 名字
static void **importSlot(const char *symbol) {
    const struct mach_header_64 *header = NULL;
    intptr_t slide = 0;
    for (uint32_t i = 0; i < _dyld_image_count() && !header; i++) {
        const struct mach_header_64 *image = (const struct mach_header_64 *)_dyld_get_image_header(i);
        if (image->magic != MH_MAGIC_64 || image->filetype != MH_EXECUTE) continue;
        header = image;
        slide = _dyld_get_image_vmaddr_slide(i);
    }
    if (!header) return NULL;

    const struct symtab_command *symtab = NULL;
    const struct dysymtab_command *dysymtab = NULL;
    const struct segment_command_64 *linkedit = NULL;
    const struct load_command *command = (const struct load_command *)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++, command = (const struct load_command *)((const char *)command + command->cmdsize)) {
        if (command->cmd == LC_SYMTAB) symtab = (const struct symtab_command *)command;
        else if (command->cmd == LC_DYSYMTAB) dysymtab = (const struct dysymtab_command *)command;
        else if (command->cmd == LC_SEGMENT_64 && !strcmp(((const struct segment_command_64 *)command)->segname, SEG_LINKEDIT)) linkedit = (const struct segment_command_64 *)command;
    }
    if (!symtab || !dysymtab || !linkedit) return NULL;
    uintptr_t base = slide + linkedit->vmaddr - linkedit->fileoff;
    const struct nlist_64 *symbols = (const struct nlist_64 *)(base + symtab->symoff);
    const char *strings = (const char *)(base + symtab->stroff);
    const uint32_t *indirect = (const uint32_t *)(base + dysymtab->indirectsymoff);

    command = (const struct load_command *)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++, command = (const struct load_command *)((const char *)command + command->cmdsize)) {
        if (command->cmd != LC_SEGMENT_64) continue;
        const struct segment_command_64 *segment = (const struct segment_command_64 *)command;
        const struct section_64 *section = (const struct section_64 *)(segment + 1);
        for (uint32_t j = 0; j < segment->nsects; j++, section++) {
            uint32_t type = section->flags & SECTION_TYPE;
            if (type != S_NON_LAZY_SYMBOL_POINTERS && type != S_LAZY_SYMBOL_POINTERS) continue;
            void **slots = (void **)(section->addr + slide);
            for (size_t k = 0; k < section->size / sizeof(void *); k++) {
                uint32_t index = indirect[section->reserved1 + k];
                if ((index & (INDIRECT_SYMBOL_ABS | INDIRECT_SYMBOL_LOCAL)) || index >= symtab->nsyms) continue;
                if (!strcmp(strings + symbols[index].n_un.n_strx, symbol)) return &slots[k];
            }
        }
    }
    return NULL;
}

static void *noTraits(void) {
    static void *empty;
    if (!empty) empty = dlsym(RTLD_DEFAULT, "_swiftEmptyArrayStorage");
    return empty;
}

static void fillImport(const char *symbol, void *replacement) {
    void **slot = importSlot(symbol);
    if (!slot || *slot) return;  // 槽里有东西说明系统自带，不用补
    vm_address_t page = (vm_address_t)slot & ~(vm_page_size - 1);
    if (vm_protect(mach_task_self(), page, vm_page_size, false, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY) != KERN_SUCCESS) return;
    *slot = replacement;
    vm_protect(mach_task_self(), page, vm_page_size, false, VM_PROT_READ);
}

static void patchOlderSystems(void) {
    class_addMethod(UITraitCollection.class, NSSelectorFromString(@"verticalBarEdge"), (IMP)verticalBarEdgeUnspecified, "q@:");
    if (noTraits()) fillImport("_$sSo17UITraitCollectionC5UIKitE36systemTraitsAffectingVerticalBarEdgeSayAC0A10Definition_pXpGvgZ", (void *)noTraits);
    gSafeAreaRegion = dlsym(RTLD_DEFAULT, "$sSo6UIViewC5UIKitE12LayoutRegionV8safeArea16cornerAdaptationA2E14AdaptivityAxisOSg_tFZ");
    if (gSafeAreaRegion) fillImport("_$sSo6UIViewC5UIKitE12LayoutRegionV3bar6onEdge6extentAESo06UIRectG0V_12CoreGraphics7CGFloatVtFZ", (void *)layoutRegionBar);
}

%ctor {
    // 只在小红书里生效。重签名常会改包名，所以再认一下可执行文件名
    NSBundle *bundle = NSBundle.mainBundle;
    if (![bundle.bundleIdentifier hasPrefix:@"com.xingin.discover"] && ![[bundle objectForInfoDictionaryKey:@"CFBundleExecutable"] isEqual:@"discover"]) return;
    // 液态玻璃是 iOS 26 的东西，更早的系统保持原样
    if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion < 26) return;

    patchOlderSystems();
    %init(XYChatBarLayout = objc_getClass("XYMessageUIKit.XYPMMessageShortcutBarLayoutViewController"),
          XYCommentHalfBar = objc_getClass("_TtCC12XYNoteModule32CommentHalflayerBottomController4View"),
          XYNativeSearchBar = objc_getClass("XYSearchBar.XYSearchBarV2"),
          XYDeviceUtility = objc_getClass("XYUIKit.DeviceUtility"),
          XYMarketRootInterface = objc_getClass("XYShopping.MarketRootInterface"),
          XYNoteDetailPage = objc_getClass("XYNoteModule.NoteDetailPageInterface"),
          XYNoteDirectionView = objc_getClass("XYNoteModule.NoteDirectionView"),
          XYVFHeadView = objc_getClass("XYOldNoteModule.VFHeadView"),
          XYVFBottomEngageView = objc_getClass("XYOldNoteModule.VFBottomEngageView"));
}
