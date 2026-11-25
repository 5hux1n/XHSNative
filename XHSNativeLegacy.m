//
//  XHSNativeLegacy.m
//  XHSNative
//
//  iOS < 26 仿液态玻璃适配与兼容层
//
#import "XHSNativeLegacy.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "XHSNativeConfig.h"
#import "XHSNativeHeaders.h"
#import "XHSNativeHelper.h"

static NSString *const kLegacyBlurKey = @"XHSNative.blur";

@implementation XHSNativeConfig (Legacy)

- (CGFloat)blurPercent {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:kLegacyBlurKey];
    return value ? MIN(MAX([value doubleValue], 0), 100) : 60;
}

- (void)setBlurPercent:(CGFloat)blur {
    [NSUserDefaults.standardUserDefaults setDouble:blur forKey:kLegacyBlurKey];
}

@end

extern const unsigned char WCShadowStart[], WCShadowEnd[], WCRimStart[], WCRimEnd[];

@interface XHSFakeGlassPlate : UIView
@property (nonatomic, strong) UIVisualEffectView *blur;
@property (nonatomic, strong) UIViewPropertyAnimator *blurAnimator;
@property (nonatomic, strong) UIView *fillView;
@property (nonatomic, strong) UIImageView *shadowView;
@property (nonatomic, strong) UIImageView *rimView;
@property (nonatomic, copy) NSString *barName;
- (void)refreshAppearance;
@end

static NSHashTable *allFakeGlassPlates(void) {
    static NSHashTable *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ table = [NSHashTable weakObjectsHashTable]; });
    return table;
}

static UIImageView *XHSArtwork(const unsigned char *start, const unsigned char *end, CGFloat cap) {
    NSData *data = [NSData dataWithBytesNoCopy:(void *)start length:(uintptr_t)end - (uintptr_t)start freeWhenDone:NO];
    UIImage *image = [UIImage imageWithData:data scale:3];
    return [[UIImageView alloc] initWithImage:[image resizableImageWithCapInsets:UIEdgeInsetsMake(0, cap, 0, cap) resizingMode:UIImageResizingModeStretch]];
}

@implementation XHSFakeGlassPlate

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        self.clipsToBounds = NO;
        UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:nil];
        blurView.layer.cornerCurve = kCACornerCurveContinuous;
        blurView.clipsToBounds = YES;
        blurView.userInteractionEnabled = NO;
        _blur = blurView;
        [self addSubview:_blur];

        _fillView = [UIView new];
        _fillView.userInteractionEnabled = NO;
        [self addSubview:_fillView];

        _shadowView = XHSArtwork(WCShadowStart, WCShadowEnd, 54);
        _shadowView.userInteractionEnabled = NO;
        [self addSubview:_shadowView];

        _rimView = XHSArtwork(WCRimStart, WCRimEnd, 32);
        _rimView.userInteractionEnabled = NO;
        [self addSubview:_rimView];

        [allFakeGlassPlates() addObject:self];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(appWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_blurAnimator stopAnimation:YES];
}

- (void)appWillEnterForeground:(NSNotification *)note {
    if (_blurAnimator) {
        [_blurAnimator stopAnimation:YES];
        _blurAnimator = nil;
    }
    [self refreshAppearance];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) {
        // 视图进窗口后再重建动画器，避免离屏阶段设置的 fractionComplete 失效导致无模糊
        if (_blurAnimator) {
            [_blurAnimator stopAnimation:YES];
            _blurAnimator = nil;
        }
        [self refreshAppearance];
    }
}

- (void)ensureBlurAnimator {
    if (!_blurAnimator || _blurAnimator.state == UIViewAnimatingStateStopped) {
        if (_blurAnimator) [_blurAnimator stopAnimation:YES];
        _blur.effect = nil;
        __weak UIVisualEffectView *weakBlur = _blur;
        _blurAnimator = [[UIViewPropertyAnimator alloc] initWithDuration:1 curve:UIViewAnimationCurveLinear animations:^{
            weakBlur.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
        }];
        _blurAnimator.pausesOnCompletion = YES;
    }
}

- (void)refreshAppearance {
    [self ensureBlurAnimator];
    BOOL dark = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    BOOL solid = UIAccessibilityIsReduceTransparencyEnabled();
    CGFloat height = CGRectGetHeight(self.bounds);
    CGFloat radius = height / 2;
    self.layer.cornerRadius = radius;
    self.layer.cornerCurve = kCACornerCurveContinuous;

    _blur.frame = self.bounds;
    _blur.layer.cornerRadius = radius;
    _fillView.frame = self.bounds;
    _fillView.layer.cornerRadius = radius;
    _fillView.layer.cornerCurve = kCACornerCurveContinuous;

    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat scale = height > 0 ? MIN(1.0, height / 60.0) : 1.0;
    CGFloat rimInset = 2.0 * scale;
    CGFloat shadowInset = 24.0 * scale;
    if (height > 0 && width > 0) {
        CGFloat rimTargetH = height + 2.0 * rimInset;
        CGFloat rimScale = rimTargetH / 64.0;
        _rimView.transform = CGAffineTransformIdentity;
        _rimView.bounds = CGRectMake(0, 0, (width + 2.0 * rimInset) / rimScale, 64.0);
        _rimView.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
        _rimView.transform = CGAffineTransformMakeScale(rimScale, rimScale);

        CGFloat shadowTargetH = height + 2.0 * shadowInset;
        CGFloat shadowScale = shadowTargetH / 108.0;
        _shadowView.transform = CGAffineTransformIdentity;
        _shadowView.bounds = CGRectMake(0, 0, (width + 2.0 * shadowInset) / shadowScale, 108.0);
        _shadowView.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
        _shadowView.transform = CGAffineTransformMakeScale(shadowScale, shadowScale);
    }

    // 与上游一致的不透明度：0 为纯玻璃，100 为完全不透明
    CGFloat fill = self.barName.length ? [XHSNativeConfig.shared fillForBar:self.barName] : 0;
    CGFloat opacity = solid ? 1.0 : MIN(MAX(fill, 0), 100) / 100.0;
    CGFloat blur = XHSNativeConfig.shared.blurPercent / 100.0;
    CGFloat fraction = blur * (0.40 + 0.60 * opacity);
    if (self.window && _blurAnimator && (_blurAnimator.state == UIViewAnimatingStateInactive || fabs(_blurAnimator.fractionComplete - fraction) > 0.001)) {
        _blurAnimator.fractionComplete = fraction;
    }
    _blur.hidden = solid || fraction <= 0.001;
    UIColor *neutral = dark ? [UIColor colorWithRed:0.13 green:0.13 blue:0.15 alpha:1] : UIColor.whiteColor;
    CGFloat fillAlpha = solid ? 1.0 : MAX(0.06, opacity * opacity);
    _fillView.backgroundColor = [neutral colorWithAlphaComponent:fillAlpha];
    _shadowView.alpha = 0.28 + 0.40 * opacity;
    _rimView.alpha = 0.30 + 0.35 * opacity;
}

- (void)setBounds:(CGRect)bounds {
    bounds.origin = CGPointZero;
    [super setBounds:bounds];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self refreshAppearance];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    [self refreshAppearance];
}

@end

#pragma mark - 渐隐边缘视图

@interface XHSFakeEdgeFadeView : UIView
@property (nonatomic, assign) BOOL fromTop;
- (void)updateColors;
@end

@implementation XHSFakeEdgeFadeView

+ (Class)layerClass {
    return CAGradientLayer.class;
}

- (void)updateColors {
    BOOL dark = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    UIColor *base = dark ? [UIColor colorWithRed:0.08 green:0.08 blue:0.09 alpha:1] : UIColor.whiteColor;
    CAGradientLayer *grad = (CAGradientLayer *)self.layer;
    if (self.fromTop) {
        grad.colors = @[
            (id)[base colorWithAlphaComponent:0.52].CGColor,
            (id)[base colorWithAlphaComponent:0.22].CGColor,
            (id)[base colorWithAlphaComponent:0.0].CGColor
        ];
        grad.locations = @[@0.0, @0.55, @1.0];
    } else {
        grad.colors = @[
            (id)[base colorWithAlphaComponent:0.0].CGColor,
            (id)[base colorWithAlphaComponent:0.22].CGColor,
            (id)[base colorWithAlphaComponent:0.52].CGColor
        ];
        grad.locations = @[@0.0, @0.45, @1.0];
    }
    grad.startPoint = CGPointMake(0.5, 0.0);
    grad.endPoint = CGPointMake(0.5, 1.0);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    [self updateColors];
}

@end

#pragma mark - 低版本底栏状态

static char kLegacyTabStateKey;

@interface XHSFakeTabBarState : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UITabBar *bar;
@property (nonatomic, strong) XHSFakeGlassPlate *capsule;
@property (nonatomic, strong) UIView *selection;
@property (nonatomic, strong) XHSFakeGlassPlate *searchPlate;
@property (nonatomic, strong) UIButton *searchButton;
@property (nonatomic, assign) BOOL lastSwapped;
@property (nonatomic, strong) UIPanGestureRecognizer *panGesture;
@property (nonatomic, strong) UITapGestureRecognizer *expandTap;
@property (nonatomic, strong) UILongPressGestureRecognizer *homeLongPress;
@property (nonatomic, assign) NSUInteger displayedIndex;
@property (nonatomic, assign) CGFloat dragStartLensX;
@property (nonatomic, assign) BOOL dragging;
@property (nonatomic, assign) BOOL minimized;
@property (nonatomic, assign) BOOL updating;
@end

@implementation XHSFakeTabBarState

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == self.homeLongPress) {
        UIViewController *homePage = [XHSNativeLegacy legacyPageForName:@"index"];
        NSUInteger homeIdx = homePage ? [self.bar.items indexOfObjectIdenticalTo:homePage.tabBarItem] : NSNotFound;
        if (homeIdx == NSNotFound) return NO;
        CGPoint loc = [gestureRecognizer locationInView:self.bar];
        if (self.minimized) {
            return self.bar.selectedItem == homePage.tabBarItem && CGRectContainsPoint(self.capsule.frame, loc);
        }
        NSMutableArray<UIView *> *buttons = [NSMutableArray array];
        for (UIView *view in self.bar.subviews) {
            if ([NSStringFromClass(view.class) isEqualToString:@"UITabBarButton"]) [buttons addObject:view];
        }
        [buttons sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
            return a.frame.origin.x < b.frame.origin.x ? NSOrderedAscending : (a.frame.origin.x > b.frame.origin.x ? NSOrderedDescending : NSOrderedSame);
        }];
        return homeIdx < buttons.count && CGRectContainsPoint(buttons[homeIdx].frame, loc);
    }
    if (gestureRecognizer == self.expandTap) {
        if (!self.minimized) return NO;
        CGPoint loc = [gestureRecognizer locationInView:self.bar];
        return CGRectContainsPoint(self.capsule.frame, loc);
    }
    if (gestureRecognizer != self.panGesture || self.minimized) return NO;
    CGPoint loc = [gestureRecognizer locationInView:self.bar];
    if (!CGRectContainsPoint(self.capsule.frame, loc)) return NO;
    CGPoint vel = [self.panGesture velocityInView:self.bar];
    return fabs(vel.x) > fabs(vel.y);
}

- (void)handleExpandTap:(UITapGestureRecognizer *)tap {
    if (tap.state == UIGestureRecognizerStateEnded && self.minimized) {
        [XHSNativeLegacy setLegacyTabBarMinimized:NO];
    }
}

- (void)handleHomeLongPress:(UILongPressGestureRecognizer *)press {
    if (press.state == UIGestureRecognizerStateBegan) [XHSNativeHelper openSettingsMenu];
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UITabBar *bar = self.bar;
    XYTabbarController *tabBarController = XHSNativeConfig.shared.tabBarController;
    if (!bar || !bar.items.count) return;
    NSUInteger count = bar.items.count;
    CGFloat capW = CGRectGetWidth(self.capsule.bounds);
    CGFloat width = count ? MIN(84, MAX(0, (capW - 6) / count)) : 0;
    CGFloat step = count > 1 ? (capW - 6 - width) / (count - 1) : 0;
    if (pan.state == UIGestureRecognizerStateBegan) {
        self.dragging = YES;
        [self.selection.layer removeAllAnimations];
        self.dragStartLensX = CGRectGetMinX(self.selection.frame);
        [UIView animateWithDuration:0.15 animations:^{
            self.selection.transform = CGAffineTransformMakeScale(1.06, 1.06);
        }];
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        CGFloat dx = [pan translationInView:self.capsule].x;
        CGFloat maxX = MAX(3, capW - 3 - width);
        CGFloat newX = MIN(maxX, MAX(3, self.dragStartLensX + dx));
        CGRect f = self.selection.frame;
        f.origin.x = newX;
        self.selection.frame = f;
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        self.dragging = NO;
        CGFloat midX = CGRectGetMidX(self.selection.frame);
        NSInteger target = step > 0 ? (NSInteger)llround((midX - 3 - width / 2.0) / step) : 0;
        target = MIN((NSInteger)count - 1, MAX(0, target));
        if (bar.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft) {
            target = (NSInteger)count - 1 - target;
        }
        [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut animations:^{
            self.selection.transform = CGAffineTransformIdentity;
        } completion:nil];
        if ((NSUInteger)target < tabBarController.viewControllers.count) {
            UIViewController *vc = tabBarController.viewControllers[target];
            if (tabBarController.selectedViewController != vc) {
                tabBarController.selectedViewController = vc;
                if ([tabBarController respondsToSelector:@selector(tabBarController:didSelectViewController:)]) {
                    [((id)tabBarController) tabBarController:tabBarController didSelectViewController:vc];
                }
            }
        }
        [XHSNativeLegacy layoutLegacyTabBar:bar];
    }
}

@end

@implementation XHSNativeLegacy

+ (BOOL)isLiquidGlassOS {
    if (@available(iOS 26.0, *)) return YES;
    return NO;
}

+ (UIView *)plateOn:(UIView *)owner key:(const void *)key below:(UIView *)below frame:(CGRect)frame bar:(NSString *)bar {
    XHSFakeGlassPlate *fake = objc_getAssociatedObject(owner, key);
    if (!fake) {
        fake = [[XHSFakeGlassPlate alloc] initWithFrame:frame];
        fake.barName = bar;
        objc_setAssociatedObject(owner, key, fake, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    BOOL empty = CGRectIsEmpty(frame) || !below.superview;
    if (fake.hidden != empty) fake.hidden = empty;
    if (empty) return fake;

    NSArray<UIView *> *siblings = below.superview.subviews;
    NSUInteger index = [siblings indexOfObjectIdenticalTo:below];
    if (fake.superview != below.superview || index == 0 || siblings[index - 1] != fake) {
        [below.superview insertSubview:fake belowSubview:below];
    }
    if (!CGRectEqualToRect(fake.frame, frame)) fake.frame = frame;
    fake.barName = bar;
    [fake refreshAppearance];
    return fake;
}

+ (void)refreshAllPlates {
    for (XHSFakeGlassPlate *glass in allFakeGlassPlates()) {
        [glass refreshAppearance];
    }
}

+ (void)darkenGlass:(UIView *)glass {
    if (glass.overrideUserInterfaceStyle != UIUserInterfaceStyleDark) glass.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    if ([glass isKindOfClass:XHSFakeGlassPlate.class]) [(XHSFakeGlassPlate *)glass refreshAppearance];
}

+ (BOOL)isGlassView:(UIView *)view {
    return [view isKindOfClass:UIVisualEffectView.class] || [view isKindOfClass:XHSFakeGlassPlate.class];
}

+ (void)applySoftEdgeFadeOn:(UIView *)bar key:(const void *)key fromTop:(BOOL)fromTop extraHeight:(CGFloat)extraHeight {
    if (!bar || CGRectIsEmpty(bar.bounds)) return;
    XHSFakeEdgeFadeView *fade = objc_getAssociatedObject(bar, key);
    if (!fade) {
        fade = [XHSFakeEdgeFadeView new];
        fade.userInteractionEnabled = NO;
        fade.fromTop = fromTop;
        objc_setAssociatedObject(bar, key, fade, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    fade.fromTop = fromTop;
    [fade updateColors];
    CGRect frame = fromTop
        ? CGRectMake(0, 0, CGRectGetWidth(bar.bounds), CGRectGetHeight(bar.bounds) + extraHeight)
        : CGRectMake(0, -extraHeight, CGRectGetWidth(bar.bounds), CGRectGetHeight(bar.bounds) + extraHeight);
    if (fade.superview != bar) [bar insertSubview:fade atIndex:0];
    else if (bar.subviews.firstObject != fade) [bar sendSubviewToBack:fade];
    if (!CGRectEqualToRect(fade.frame, frame)) fade.frame = frame;
}

+ (UIButton *)glassIconButtonWithSymbol:(NSString *)symbolName label:(NSString *)label handler:(void (^)(void))handler {
    UIImageSymbolConfiguration *sym = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium];
    UIButton *button = nil;
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
        config.image = [UIImage systemImageNamed:symbolName];
        config.preferredSymbolConfigurationForImage = sym;
        config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
        config.baseForegroundColor = UIColor.labelColor;
        button = [UIButton buttonWithConfiguration:config primaryAction:[UIAction actionWithHandler:^(UIAction *action) {
            if (handler) handler();
        }]];
    } else {
        button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setImage:[UIImage systemImageNamed:symbolName withConfiguration:sym] forState:UIControlStateNormal];
        button.tintColor = UIColor.labelColor;
        [button addAction:[UIAction actionWithHandler:^(UIAction *action) {
            if (handler) handler();
        }] forControlEvents:UIControlEventTouchUpInside];
    }
    button.accessibilityLabel = label;
    return button;
}

+ (UIViewController *)legacyPageForName:(NSString *)name {
    XHSNativeConfig *config = XHSNativeConfig.shared;
    if ([config isTabHidden:name]) return nil;
    NSUInteger index = [config.pageNames indexOfObject:name];
    return (index != NSNotFound && index < config.pages.count) ? config.pages[index] : nil;
}

+ (BOOL)isControllerTabBarHidden:(UITabBarController *)controller {
    if ([controller respondsToSelector:@selector(isTabBarHidden)]) {
        return ((BOOL (*)(id, SEL))objc_msgSend)(controller, @selector(isTabBarHidden));
    }
    return controller.tabBar.hidden;
}

+ (void)rebuildLegacyTabs {
    XHSNativeConfig *config = XHSNativeConfig.shared;
    XYTabbarController *controller = config.tabBarController;
    if (!controller || !config.pages.count) return;
    config.tabsDirty = [self isControllerTabBarHidden:controller];
    if (config.tabsDirty) return;

    NSArray *legacyNames = [XHSNativeHelper legacyTabNames:controller];
    NSDictionary<NSNumber *, NSString *> *badgeDict = [controller respondsToSelector:@selector(badgeValueDict)] ? controller.badgeValueDict : nil;
    UIViewController *selected = controller.selectedViewController;
    NSMutableArray<UIViewController *> *ordered = [NSMutableArray array];
    for (NSString *name in config.tabOrder) {
        NSUInteger index = [config.pageNames indexOfObject:name];
        if (index == NSNotFound || [config isTabHidden:name]) continue;
        UIViewController *page = config.pages[index];
        page.tabBarItem.title = nil;
        page.tabBarItem.image = [XHSNativeHelper tabIcon:name selected:NO];
        page.tabBarItem.selectedImage = [XHSNativeHelper tabIcon:name selected:YES];
        page.tabBarItem.imageInsets = UIEdgeInsetsMake(6, 0, -6, 0);
        NSUInteger badgeIndex = [legacyNames indexOfObject:name];
        if (legacyNames && badgeIndex != NSNotFound) {
            id raw = badgeDict[@(badgeIndex)];
            page.tabBarItem.badgeValue = ([raw isKindOfClass:NSString.class] && [raw length]) ? raw : nil;
        }
        [ordered addObject:page];
    }
    config.rebuilding = YES;
    [controller setViewControllers:ordered animated:NO];
    for (UITabBarItem *item in controller.tabBar.items) {
        if (item.badgeValue) [XHSNativeHelper refreshBadge:item];
    }
    if (selected && [ordered containsObject:selected]) controller.selectedViewController = selected;
    if (ordered.count) controller.customtabBar.alpha = 0;
    config.rebuilding = NO;
    [controller.tabBar setNeedsLayout];
    [self layoutLegacyTabBar:controller.tabBar];
}

+ (void)setLegacyTabBarMinimized:(BOOL)minimized {
    XYTabbarController *controller = XHSNativeConfig.shared.tabBarController;
    if ([self isLiquidGlassOS] || !controller) return;
    UITabBar *bar = controller.tabBar;
    XHSFakeTabBarState *state = objc_getAssociatedObject(bar, &kLegacyTabStateKey);
    if (!state) return;
    if (![XHSNativeConfig.shared boolForKey:kXHSNativeMinimize]) minimized = NO;
    if (state.minimized == minimized) return;
    state.minimized = minimized;
    [UIView animateWithDuration:0.32 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0.4 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        [self layoutLegacyTabBar:bar];
    } completion:nil];
}

+ (void)layoutLegacyTabBar:(UITabBar *)bar {
    XYTabbarController *controller = XHSNativeConfig.shared.tabBarController;
    if ([self isLiquidGlassOS] || !controller || bar != controller.tabBar || !bar.window) return;
    XHSFakeTabBarState *state = objc_getAssociatedObject(bar, &kLegacyTabStateKey);
    if (state.updating || state.dragging) return;
    BOOL swapped = XHSNativeConfig.shared.isPublishSwapped;
    if (!state) {
        state = [XHSFakeTabBarState new];
        state.bar = bar;
        state.displayedIndex = NSNotFound;

        state.capsule = [XHSFakeGlassPlate new];
        state.capsule.barName = kXHSNativeBarHome;

        state.selection = [UIView new];
        state.selection.userInteractionEnabled = NO;
        [state.capsule addSubview:state.selection];

        state.searchPlate = [XHSFakeGlassPlate new];
        state.searchPlate.barName = kXHSNativeBarHome;

        state.panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:state action:@selector(handlePan:)];
        state.panGesture.delegate = state;
        [bar addGestureRecognizer:state.panGesture];

        state.expandTap = [[UITapGestureRecognizer alloc] initWithTarget:state action:@selector(handleExpandTap:)];
        state.expandTap.delegate = state;
        [bar addGestureRecognizer:state.expandTap];

        state.homeLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:state action:@selector(handleHomeLongPress:)];
        state.homeLongPress.minimumPressDuration = 0.45;
        state.homeLongPress.delegate = state;
        [bar addGestureRecognizer:state.homeLongPress];

        objc_setAssociatedObject(bar, &kLegacyTabStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (!state.searchButton || state.lastSwapped != swapped) {
        [state.searchButton removeFromSuperview];
        state.lastSwapped = swapped;
        state.searchButton = [self glassIconButtonWithSymbol:(swapped ? @"plus" : @"magnifyingglass")
                                                      label:(swapped ? @"发布" : @"搜索")
                                                    handler:^{
            if (XHSNativeConfig.shared.isPublishSwapped) [XHSNativeHelper openPublish];
            else [XHSNativeHelper openSearch];
        }];
    }

    state.updating = YES;
    void (^applyLayout)(void) = ^{
        CGFloat barWidth = CGRectGetWidth(bar.bounds);
        CGFloat barHeight = CGRectGetHeight(bar.bounds);
        CGFloat safeBottom = bar.safeAreaInsets.bottom;
        CGFloat height = MIN(56, MAX(0, barHeight - 2));
        CGFloat y = MAX(2, safeBottom > 0 ? barHeight - MAX(0, safeBottom - 8) - height : barHeight - height);
        BOOL showSearch = [XHSNativeConfig.shared boolForKey:kXHSNativeSearchTab] || swapped;
        CGFloat sideInset = 18;
        CGFloat searchGap = 10;
        CGFloat searchSize = height;
        NSUInteger count = bar.items.count;
        CGFloat maxCapsuleWidth = showSearch ? MAX(0, barWidth - 2 * sideInset - searchSize - searchGap)
                                             : MAX(0, barWidth - 2 * sideInset);
        CGFloat fullCapsuleWidth = count ? MIN(maxCapsuleWidth, MAX(height, count * 84.0 + 6.0)) : height;
        CGFloat capsuleWidth = state.minimized ? height : fullCapsuleWidth;
        CGRect capsuleFrame = CGRectMake(sideInset, y, capsuleWidth, height);

        for (UIView *view in bar.subviews) {
            NSString *clsName = NSStringFromClass(view.class);
            if ([clsName isEqualToString:@"_UIBarBackground"]) {
                if (!view.hidden) view.hidden = YES;
            } else if ([clsName isEqualToString:@"XYTabBar"]) {
                view.alpha = 0;
                view.hidden = YES;
                view.userInteractionEnabled = NO;
            }
        }
        static char kTabFadeKey;
        [self applySoftEdgeFadeOn:bar key:&kTabFadeKey fromTop:NO extraHeight:10];

        if (state.capsule.superview != bar) [bar insertSubview:state.capsule atIndex:MIN(1, bar.subviews.count)];
        state.capsule.hidden = NO;
        state.capsule.alpha = 1.0;
        if (!CGRectEqualToRect(state.capsule.frame, capsuleFrame)) state.capsule.frame = capsuleFrame;
        [state.capsule refreshAppearance];

        state.searchPlate.hidden = !showSearch;
        state.searchButton.hidden = !showSearch;
        if (showSearch) {
            CGFloat searchX = barWidth - sideInset - searchSize;
            CGRect searchFrame = CGRectMake(searchX, y, searchSize, searchSize);
            if (state.searchPlate.superview != bar) [bar addSubview:state.searchPlate];
            if (state.searchButton.superview != bar) [bar addSubview:state.searchButton];
            if (!CGRectEqualToRect(state.searchPlate.frame, searchFrame)) state.searchPlate.frame = searchFrame;
            if (!CGRectEqualToRect(state.searchButton.frame, searchFrame)) state.searchButton.frame = searchFrame;
            [state.searchPlate refreshAppearance];
            [bar bringSubviewToFront:state.searchPlate];
            [bar bringSubviewToFront:state.searchButton];
        }

        CGFloat width = count ? MIN(84, MAX(0, (fullCapsuleWidth - 6) / count)) : 0;
        CGFloat step = count > 1 ? (fullCapsuleWidth - 6 - width) / (count - 1) : 0;

        NSMutableArray<UIView *> *buttons = [NSMutableArray array];
        for (UIView *view in bar.subviews) {
            if ([NSStringFromClass(view.class) isEqualToString:@"UITabBarButton"]) [buttons addObject:view];
        }
        [buttons sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
            return a.frame.origin.x < b.frame.origin.x ? NSOrderedAscending : (a.frame.origin.x > b.frame.origin.x ? NSOrderedDescending : NSOrderedSame);
        }];

        NSUInteger selected = bar.selectedItem ? [bar.items indexOfObjectIdenticalTo:bar.selectedItem] : NSNotFound;
        for (NSUInteger i = 0; i < buttons.count && i < count; i++) {
            UIView *btn = buttons[i];
            if (btn.hidden) btn.hidden = NO;
            btn.layer.sublayerTransform = CATransform3DIdentity;
            if (state.minimized) {
                BOOL isActive = (i == selected) || (selected == NSNotFound && i == 0);
                btn.alpha = isActive ? 1.0 : 0.0;
                btn.userInteractionEnabled = NO;
                CGRect btnFrame = CGRectMake(sideInset, CGRectGetMinY(capsuleFrame) + 3, height, height - 6);
                if (!CGRectEqualToRect(btn.frame, btnFrame)) btn.frame = btnFrame;
            } else {
                btn.alpha = 1.0;
                btn.userInteractionEnabled = YES;
                CGRect btnFrame = CGRectMake(CGRectGetMinX(capsuleFrame) + 3 + i * step, CGRectGetMinY(capsuleFrame) + 3, width, height - 6);
                if (!CGRectEqualToRect(btn.frame, btnFrame)) btn.frame = btnFrame;
            }
        }

        BOOL dark = bar.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
        if (selected < count && !state.minimized) {
            NSUInteger physical = bar.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft ? count - 1 - selected : selected;
            CGRect target = CGRectMake(3 + physical * step, 3, width, height - 6);
            CALayer *lens = state.selection.layer;
            NSString *key = @"xhs.selection.slide";
            BOOL changed = state.displayedIndex != NSNotFound && state.displayedIndex != selected;
            BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
            if (!CGRectEqualToRect(state.selection.frame, target)) {
                CGFloat start = lens.position.x;
                if ([lens animationForKey:key] && lens.presentationLayer) start = lens.presentationLayer.position.x;
                BOOL slide = changed && CGSizeEqualToSize(state.selection.bounds.size, target.size) && !reduceMotion;
                state.selection.frame = target;
                if (slide) {
                    CABasicAnimation *motion = [CABasicAnimation animationWithKeyPath:@"position.x"];
                    motion.fromValue = @(start);
                    motion.toValue = @(CGRectGetMidX(target));
                    motion.duration = 0.28;
                    motion.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
                    [lens addAnimation:motion forKey:key];
                } else {
                    [lens removeAnimationForKey:key];
                }
            }
            if (reduceMotion) [lens removeAnimationForKey:key];
            state.displayedIndex = selected;
            state.selection.layer.cornerRadius = (height - 6) / 2;
            state.selection.layer.cornerCurve = kCACornerCurveContinuous;
            state.selection.backgroundColor = [UIColor colorWithWhite:dark ? 1 : 0 alpha:dark ? 0.16 : 0.08];
            state.selection.alpha = 1.0;
            state.selection.hidden = NO;
        } else {
            state.displayedIndex = selected;
            [state.selection.layer removeAnimationForKey:@"xhs.selection.slide"];
            state.selection.alpha = 0.0;
        }
    };
    if ([UIView areAnimationsEnabled]) applyLayout();
    else [UIView performWithoutAnimation:applyLayout];
    state.updating = NO;
}

+ (void)handleScrollPan:(UIPanGestureRecognizer *)pan inPage:(UIViewController *)page {
    if ([self isLiquidGlassOS]) return;
    UIScrollView *list = (UIScrollView *)pan.view;
    if (pan.state == UIGestureRecognizerStateChanged && [XHSNativeConfig.shared boolForKey:kXHSNativeMinimize]) {
        CGFloat vy = [pan velocityInView:list].y;
        if (vy < -180) [self setLegacyTabBarMinimized:YES];
        else if (vy > 180) [self setLegacyTabBarMinimized:NO];
    }
    UIView *homeBar = XHSNativeConfig.shared.homeBar;
    if (homeBar && [list isDescendantOfView:homeBar.superview]) {
        [self extendHomeFeedUnderNaviBar:homeBar];
    }
}

#pragma mark - 首页延伸 / 二级频道栏 / 悬浮提示

static void adjustFloatingPillsUnderBar(UIView *container, UIView *root, UIView *skip, CGFloat barBottom, CGFloat maxW) {
    for (UIView *v in container.subviews) {
        if (v == skip || v.hidden || v.alpha <= 0.01) continue;
        CGFloat w = CGRectGetWidth(v.bounds);
        CGFloat h = CGRectGetHeight(v.bounds);
        if (![v isKindOfClass:UIScrollView.class] && h >= 24 && h <= 56 && w > 60 && w < maxW - 40) {
            CGFloat rawY = v.center.y - h / 2.0;
            CGFloat rootY = [root convertPoint:CGPointMake(0, rawY) fromView:container].y;
            if (rootY < barBottom + 4) {
                v.transform = CGAffineTransformMakeTranslation(0, barBottom + 8 - rootY);
            }
        }
    }
}

static void applyHomeTopInset(UIView *view, CGFloat targetTop, CGFloat topNeed) {
    if ([view isKindOfClass:UIScrollView.class]) {
        UIScrollView *sv = (UIScrollView *)view;
        if (CGRectGetHeight(sv.bounds) < 200) return;
        if (!sv.pagingEnabled) {
            if (sv.adjustedContentInset.top < targetTop - 1) {
                UIEdgeInsets inset = sv.contentInset;
                inset.top = MAX(inset.top, topNeed);
                sv.contentInset = inset;
                sv.scrollIndicatorInsets = inset;
            }
            return;
        }
    }
    for (UIView *sub in view.subviews) {
        applyHomeTopInset(sub, targetTop, topNeed);
    }
}

+ (void)extendHomeFeedUnderNaviBar:(UIView *)naviBar {
    if ([self isLiquidGlassOS] || !naviBar.superview) return;
    UIView *root = naviBar.superview;
    CGFloat barBottom = CGRectGetMaxY(naviBar.frame);
    if (barBottom <= 0) return;
    CGFloat safeTop = root.window.safeAreaInsets.top;
    for (UIView *sub in root.subviews) {
        for (UIView *child in sub.subviews) {
            if (![child isKindOfClass:UIScrollView.class]) continue;
            UIScrollView *pager = (UIScrollView *)child;
            if (!pager.pagingEnabled) continue;
            CGFloat pageH = CGRectGetHeight(pager.bounds);
            for (UIView *page in pager.subviews) {
                UIView *topChannelBar = nil;
                CGFloat channelBarH = 0;
                CGFloat channelRawY = 0;
                for (UIView *item in page.subviews) {
                    if (item.hidden) continue;
                    CGFloat rawY = item.center.y - CGRectGetHeight(item.bounds) / 2.0;
                    CGFloat h = CGRectGetHeight(item.bounds);
                    if (![item isKindOfClass:UIScrollView.class] && rawY >= -h - 5 && rawY < 20 && h > 20 && h < 80) {
                        topChannelBar = item;
                        channelBarH = h;
                        channelRawY = rawY;
                        break;
                    }
                }
                if (CGRectGetMinY(page.frame) > 1 && fabs(CGRectGetMinY(page.frame) - barBottom) < 20) {
                    CGRect pf = page.frame;
                    pf.origin.y = 0;
                    pf.size.height = pageH;
                    page.frame = pf;
                }
                if (topChannelBar) {
                    BOOL collapsed = (channelRawY < -1 && topChannelBar.center.y < -1);
                    topChannelBar.alpha = collapsed ? 0.0 : 1.0;
                    topChannelBar.transform = CGAffineTransformMakeTranslation(0, barBottom);
                    [XHSNativeHelper clearBackground:topChannelBar];
                    for (UIView *subView in topChannelBar.subviews) {
                        if (![subView isKindOfClass:UICollectionView.class] && ![subView isKindOfClass:UIButton.class] && subView.alpha > 0) {
                            subView.alpha = 0;
                        }
                    }
                }
                CGFloat targetTop = barBottom + channelBarH;
                CGFloat topNeed = MAX(0, targetTop - safeTop);
                CGFloat pageW = CGRectGetWidth(page.bounds);
                adjustFloatingPillsUnderBar(page, root, topChannelBar, targetTop, pageW);
                for (UIView *item in page.subviews) {
                    if (item == topChannelBar) continue;
                    if (CGRectGetMinY(item.frame) < 0 && CGRectGetMaxY(item.frame) <= 1 && !item.subviews.count && item.alpha > 0) {
                        item.alpha = 0;
                    }
                    if (topChannelBar && CGRectGetMinY(item.frame) > 1 && CGRectGetMinY(item.frame) <= channelBarH + 20 && CGRectGetHeight(item.frame) > pageH * 0.5) {
                        if (!item.translatesAutoresizingMaskIntoConstraints) {
                            for (NSLayoutConstraint *c in page.constraints) {
                                if (c.firstItem == item && c.firstAttribute == NSLayoutAttributeTop) {
                                    if (c.secondItem == topChannelBar && c.secondAttribute == NSLayoutAttributeBottom) {
                                        if (fabs(c.constant + channelBarH) > 0.5) c.constant = -channelBarH;
                                    } else if (c.secondItem == page && c.secondAttribute == NSLayoutAttributeTop) {
                                        if (fabs(c.constant) > 0.5) c.constant = 0;
                                    }
                                }
                            }
                        }
                        CGRect sf = item.frame;
                        sf.origin.y = 0;
                        sf.size.height = pageH;
                        item.frame = sf;
                    }
                    adjustFloatingPillsUnderBar(item, root, nil, targetTop, pageW);
                    if ([item.subviews.firstObject isKindOfClass:UIScrollView.class]) {
                        UIScrollView *innerPager = (UIScrollView *)item.subviews.firstObject;
                        for (UIView *subPage in innerPager.subviews) {
                            adjustFloatingPillsUnderBar(subPage, root, nil, targetTop, pageW);
                        }
                    }
                    applyHomeTopInset(item, targetTop, topNeed);
                }
            }
        }
    }
}

#pragma mark - 个人页 / 笔记页低版本补丁

+ (void)layoutProfileBar:(XYPFProfileV2NavigationBar *)bar {
    static char leftKey, rightKey;
    UIView *menu = [bar homeMenuButton];
    UIView *share = [bar shareButton], *scan = [bar scanButton], *edit = [bar editButton];
    BOOL enabled = [XHSNativeConfig.shared boolForKey:kXHSNativeGlassProfile] && ![bar usesDuoNavigation] && [XHSNativeHelper isVisible:menu] && menu.superview == bar;

    CGRect menuFrame = menu.frame;
    CGFloat barW = CGRectGetWidth(bar.bounds);
    CGFloat y = CGRectGetMinY(menuFrame);
    CGFloat h = CGRectGetHeight(menuFrame);
    if (h <= 0) h = 36;
    if (y <= 0 && bar.superview) y = bar.window ? MAX(bar.window.safeAreaInsets.top + 4, 44) : 44;

    if (enabled && CGRectGetWidth(menuFrame) > 0) {
        [self plateOn:bar key:&leftKey below:menu frame:CGRectInset(menuFrame, -6, -6) bar:kXHSNativeBarProfile];
    } else {
        ((UIView *)objc_getAssociatedObject(bar, &leftKey)).hidden = YES;
    }

    NSMutableArray<UIView *> *rightBtns = [NSMutableArray array];
    for (UIView *button in @[edit ?: [NSNull null], scan ?: [NSNull null], share ?: [NSNull null]]) {
        if ((id)button == [NSNull null] || button.superview != bar || button.hidden || button.alpha <= 0.01) continue;
        [rightBtns addObject:button];
    }
    if (enabled && rightBtns.count && barW > 0) {
        CGFloat x = barW - 14;
        CGRect group = CGRectNull;
        for (NSInteger idx = (NSInteger)rightBtns.count - 1; idx >= 0; idx--) {
            UIView *btn = rightBtns[idx];
            CGSize sz = btn.bounds.size;
            if (sz.width <= 0) sz = CGSizeMake(h, h);
            x -= sz.width;
            CGRect f = CGRectMake(x, y + (h - sz.height) / 2, sz.width, sz.height);
            if (!CGRectEqualToRect(btn.frame, f)) btn.frame = f;
            group = CGRectUnion(group, f);
            x -= 8;
        }
        // 取 bar.subviews 中层级最靠下的按钮作为 below 目标，避免玻璃底板盖住其他按钮（如 share）
        UIView *lowest = nil;
        for (UIView *sub in bar.subviews) {
            if ([rightBtns containsObject:sub]) {
                lowest = sub;
                break;
            }
        }
        if (lowest && !CGRectIsNull(group)) {
            [self plateOn:bar key:&rightKey below:lowest frame:CGRectInset(group, -6, -6) bar:kXHSNativeBarProfile];
        } else {
            ((UIView *)objc_getAssociatedObject(bar, &rightKey)).hidden = YES;
        }
    } else {
        ((UIView *)objc_getAssociatedObject(bar, &rightKey)).hidden = YES;
    }
}

+ (void)adjustNoteBottomInStack:(UIView *)stack {
    UIView *editField = nil;
    for (UIView *group in stack.subviews) {
        for (UIView *field in group.subviews) {
            if ([NSStringFromClass(field.class) hasSuffix:@"InteractionEditField"] && !field.hidden) editField = field;
        }
    }
    if (editField) {
        editField.transform = CGAffineTransformMakeTranslation(6, 0);
    }
}

@end
