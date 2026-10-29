//
//  Flying_ToastersView.m
//  Flying Toasters
//
//  Created by Linus Lundahl on 2026-10-28.
//
//  A faithful recreation of Berkeley Systems' "Flying Toasters" (After Dark),
//  based on the CSS implementation by Bryan Braun (after-dark-css, MIT license).
//  Sprites extracted from https://www.bryanbraun.com/after-dark-css/
//

#import "Flying_ToastersView.h"

/// Flap animation: 4 frames, 0.2s per full cycle, alternating direction.
static const NSTimeInterval kFlapCycleDuration = 0.2;
static const NSInteger kFlapFrameCount = 4;

/// Sprite edge length in points (the original GIFs are 64x64).
static const CGFloat kSpriteSize = 64.0;

typedef NS_ENUM(NSInteger, FTObjectKind) {
    FTObjectKindToaster,
    FTObjectKindToast
};

@interface FTFlyingObject : NSObject
@property (nonatomic) FTObjectKind kind;
/// Starting position as CSS fractions: x = `right` % of width, y = `top` %
/// of height (matching the original right/top percentage pairs). Negative
/// values mean the object sits beyond that edge (off-screen).
@property (nonatomic) NSPoint anchor;
/// Duration of one full flight across the screen, in seconds.
@property (nonatomic) NSTimeInterval period;
/// Delay before the first flight begins, in seconds.
@property (nonatomic) NSTimeInterval delay;
/// YES if the flap animation plays in reverse (out of sequence).
@property (nonatomic) BOOL flapReverse;
/// Per-object offset (in points) along the flight direction, used to spread
/// same-speed objects so they don't ride on top of each other.
@property (nonatomic) CGFloat scatter;
/// Per-object lateral offset in [-1, 1) across the entry corner, shifting the
/// start point along the top/right edges so entry positions vary.
@property (nonatomic) CGFloat lane;
@end

@implementation FTFlyingObject
@end

@implementation Flying_ToastersView {
    NSImage *_toasterSprite; // 256x64, four 64x64 frames
    NSImage *_toastImage;    // 64x64
    NSArray<FTFlyingObject *> *_objects;
    NSDate *_startDate;
    NSTimeInterval _elapsedOverride; // test hook; NAN when unused
    NSUInteger _screenSeed;   // stable per-screen seed; varies the pattern
}

/// Test hook: when set to a non-NAN value, animateOneFrame uses this elapsed
/// time instead of wall clock. Not used by the screensaver itself.
- (void)testSetElapsedOverride:(NSTimeInterval)elapsed
{
    _elapsedOverride = elapsed;
}

/// Test hook: force the per-screen seed. Not used by the screensaver itself.
- (void)testSetSeed:(NSUInteger)seed
{
    _screenSeed = seed;
    _objects = [self buildObjects];
}

- (NSTimeInterval)currentElapsed
{
    if (!isnan(_elapsedOverride)) {
        return _elapsedOverride;
    }
    return [[NSDate date] timeIntervalSinceDate:_startDate];
}

- (instancetype)initWithFrame:(NSRect)frame isPreview:(BOOL)isPreview
{
    self = [super initWithFrame:frame isPreview:isPreview];
    if (self) {
        [self setAnimationTimeInterval:1.0 / 60.0];
        _startDate = [NSDate date];
        _elapsedOverride = NAN;

        NSBundle *bundle = [NSBundle bundleForClass:[self class]];
        _toasterSprite = [bundle imageForResource:@"toaster-sprite"];
        _toastImage = [bundle imageForResource:@"toast1"];

        // Default seed from the view frame's global position. startAnimation
        // refines this from the actual NSScreen once we're in a window.
        _screenSeed = [self seedFromScreenFrame:frame];

        _objects = [self buildObjects];
    }
    return self;
}

/// Derives a stable seed from a frame's position/size so each physical
/// screen (which sits at a distinct global origin) gets a distinct pattern.
- (NSUInteger)seedFromScreenFrame:(NSRect)frame
{
    NSUInteger h = 1469598103934665603ull; // FNV-1a offset basis
    NSUInteger values[] = {
        (NSUInteger)frame.origin.x, (NSUInteger)frame.origin.y,
        (NSUInteger)frame.size.width, (NSUInteger)frame.size.height
    };
    for (int i = 0; i < 4; i++) {
        NSUInteger v = values[i];
        for (int b = 0; b < 8; b++) {
            h ^= (v & 0xff);
            h *= 1099511628211ull; // FNV prime
            v >>= 8;
        }
    }
    return h;
}

/// Recreates the full object roster from the original CSS implementation:
/// kinds (toaster/toast), animation classes (t1..t9, tst1..tst4), and
/// positions (p6..p33) with their right/top percentages.
- (NSArray<FTFlyingObject *> *)buildObjects
{
    // Raw CSS positions from the original implementation: { right %, top % }.
    // Negative values place the object beyond the top/right edges (off-screen).
    NSDictionary<NSNumber *, NSArray<NSNumber *> *> *positions = @{
        @6:  @[@-2,  @-17], @7:  @[@10,  @-19], @8:  @[@20,  @-18],
        @9:  @[@30,  @-20], @10: @[@40,  @-21], @11: @[@50,  @-18],
        @12: @[@60,  @-20], @13: @[@-17, @10],  @14: @[@-19, @20],
        @15: @[@-21, @30],  @16: @[@-23, @50],  @17: @[@-25, @70],
        @18: @[@0,   @-26], @19: @[@10,  @-20], @20: @[@20,  @-36],
        @21: @[@30,  @-24], @22: @[@40,  @-33], @23: @[@60,  @-40],
        @24: @[@-26, @10],  @25: @[@-36, @30],  @26: @[@-29, @50],
        @27: @[@0,   @-46], @28: @[@10,  @-56], @29: @[@20,  @-49],
        @30: @[@30,  @-60], @31: @[@-46, @10],  @32: @[@-56, @20],
        @33: @[@-49, @30],
    };

    // Flight parameters from the animation classes:
    //   key:   period, delay, flapReverse
    //   t1:    10s, 0s,  NO     t2: 16s, 0s,  YES    t3: 24s, 0s,  NO
    //   t4:    10s, 5s,  NO     t5: 24s, 4s,  YES    t6: 24s, 8s,  NO
    //   t7:    24s, 12s, YES    t8: 24s, 16s, NO     t9: 24s, 20s, YES
    //   tst1:  10s, 0s          tst2: 16s, 0s
    //   tst3:  24s, 0s          tst4: 24s, 12s
    NSArray<NSArray<id> *> *roster = @[
        // kind,        period, delay, flapReverse, position
        @[ @(FTObjectKindToaster), @10.0, @0.0,  @NO,  @6  ], // t1
        @[ @(FTObjectKindToaster), @24.0, @0.0,  @NO,  @7  ], // t3
        @[ @(FTObjectKindToast),   @10.0, @0.0,  @NO,  @8  ], // tst1
        @[ @(FTObjectKindToaster), @24.0, @0.0,  @NO,  @9  ], // t3
        @[ @(FTObjectKindToaster), @10.0, @0.0,  @NO,  @11 ], // t1
        @[ @(FTObjectKindToaster), @24.0, @0.0,  @NO,  @12 ], // t3
        @[ @(FTObjectKindToaster), @16.0, @0.0,  @YES, @13 ], // t2
        @[ @(FTObjectKindToast),   @24.0, @0.0,  @NO,  @14 ], // tst3
        @[ @(FTObjectKindToast),   @16.0, @0.0,  @NO,  @16 ], // tst2
        @[ @(FTObjectKindToaster), @10.0, @0.0,  @NO,  @17 ], // t1
        @[ @(FTObjectKindToast),   @16.0, @0.0,  @NO,  @19 ], // tst2
        @[ @(FTObjectKindToast),   @24.0, @0.0,  @NO,  @20 ], // tst3
        @[ @(FTObjectKindToaster), @16.0, @0.0,  @YES, @21 ], // t2
        @[ @(FTObjectKindToast),   @10.0, @0.0,  @NO,  @24 ], // tst1
        @[ @(FTObjectKindToaster), @10.0, @0.0,  @NO,  @22 ], // t1
        @[ @(FTObjectKindToast),   @16.0, @0.0,  @NO,  @26 ], // tst2
        @[ @(FTObjectKindToaster), @10.0, @0.0,  @NO,  @28 ], // t1
        @[ @(FTObjectKindToast),   @16.0, @0.0,  @NO,  @30 ], // tst2
        @[ @(FTObjectKindToaster), @16.0, @0.0,  @YES, @31 ], // t2
        @[ @(FTObjectKindToaster), @10.0, @0.0,  @NO,  @32 ], // t1
        @[ @(FTObjectKindToast),   @24.0, @0.0,  @NO,  @33 ], // tst3

        // Wave 1 (fast, delayed) — t4
        @[ @(FTObjectKindToaster), @10.0, @5.0,  @NO,  @27 ],
        @[ @(FTObjectKindToaster), @10.0, @5.0,  @NO,  @10 ],
        @[ @(FTObjectKindToaster), @10.0, @5.0,  @NO,  @25 ],
        @[ @(FTObjectKindToaster), @10.0, @5.0,  @NO,  @29 ],

        // Wave 2 — t5
        @[ @(FTObjectKindToaster), @24.0, @4.0,  @YES, @15 ],
        @[ @(FTObjectKindToaster), @24.0, @4.0,  @YES, @18 ],
        @[ @(FTObjectKindToaster), @24.0, @4.0,  @YES, @22 ],

        // Wave 3 — t6
        @[ @(FTObjectKindToaster), @24.0, @8.0,  @NO,  @6  ],
        @[ @(FTObjectKindToaster), @24.0, @8.0,  @NO,  @11 ],
        @[ @(FTObjectKindToaster), @24.0, @8.0,  @NO,  @15 ],
        @[ @(FTObjectKindToaster), @24.0, @8.0,  @NO,  @19 ],
        @[ @(FTObjectKindToaster), @24.0, @8.0,  @NO,  @23 ],

        // Wave 4 (delayed toast) — tst4
        @[ @(FTObjectKindToast),   @24.0, @12.0, @NO,  @10 ],
        @[ @(FTObjectKindToast),   @24.0, @12.0, @NO,  @23 ],
        @[ @(FTObjectKindToast),   @24.0, @12.0, @NO,  @15 ],

        // Wave 5 — t7
        @[ @(FTObjectKindToaster), @24.0, @12.0, @YES, @7  ],
        @[ @(FTObjectKindToaster), @24.0, @12.0, @YES, @12 ],
        @[ @(FTObjectKindToaster), @24.0, @12.0, @YES, @16 ],
        @[ @(FTObjectKindToaster), @24.0, @12.0, @YES, @20 ],
        @[ @(FTObjectKindToaster), @24.0, @12.0, @YES, @24 ],

        // Wave 6 — t8
        @[ @(FTObjectKindToaster), @24.0, @16.0, @NO,  @8  ],
        @[ @(FTObjectKindToaster), @24.0, @16.0, @NO,  @13 ],
        @[ @(FTObjectKindToaster), @24.0, @16.0, @NO,  @17 ],
        @[ @(FTObjectKindToaster), @24.0, @16.0, @NO,  @25 ],

        // Wave 7 — t9
        @[ @(FTObjectKindToaster), @24.0, @20.0, @YES, @14 ],
        @[ @(FTObjectKindToaster), @24.0, @20.0, @YES, @18 ],
        @[ @(FTObjectKindToaster), @24.0, @20.0, @YES, @21 ],
        @[ @(FTObjectKindToaster), @24.0, @20.0, @YES, @26 ],
    ];

    // Shuffle the roster with a Fisher–Yates pass seeded per screen. This
    // keeps the same fleet composition (same kinds, speeds, delays) but
    // reassigns them to different entry positions, so each monitor runs a
    // genuinely different animation instead of the same choreography with
    // only small offsets.
    NSMutableArray<NSArray<id> *> *shuffled = [roster mutableCopy];
    for (NSInteger i = (NSInteger)shuffled.count - 1; i > 0; i--) {
        NSUInteger r = _screenSeed ^ ((NSUInteger)i * 2654435761u);
        r ^= r >> 13; r *= 1103515245u; r ^= r >> 16;
        NSInteger j = (NSInteger)(r % ((NSUInteger)i + 1));
        [shuffled exchangeObjectAtIndex:(NSUInteger)i withObjectAtIndex:(NSUInteger)j];
    }

    NSMutableArray<FTFlyingObject *> *objects = [NSMutableArray arrayWithCapacity:shuffled.count];
    NSUInteger index = 0;
    for (NSArray<id> *entry in shuffled) {
        NSNumber *positionKey = entry[4];
        NSArray<NSNumber *> *pos = positions[positionKey];
        if (!pos) { continue; }

        FTFlyingObject *object = [[FTFlyingObject alloc] init];
        object.kind = [entry[0] integerValue];
        object.period = [entry[1] doubleValue];
        object.delay = [entry[2] doubleValue];
        object.flapReverse = [entry[3] boolValue];
        object.anchor = NSMakePoint(pos[0].doubleValue / 100.0,
                                    pos[1].doubleValue / 100.0);

        // Deterministic pseudo-random values in [-1, 1), hashed from the
        // index AND the per-screen seed so each monitor gets a different
        // pattern of entry positions and timing.
        NSUInteger x = (index + 1) * 2654435761u ^ (_screenSeed * 2246822519u);
        x ^= x >> 13; x *= 1103515245u; x ^= x >> 16;
        object.scatter = ((double)(x % 2000) / 1000.0) - 1.0;

        NSUInteger y = (index + 1) * 2246822519u ^ (_screenSeed * 2654435761u);
        y ^= y >> 13; y *= 1103515245u; y ^= y >> 16;
        object.lane = ((double)(y % 2000) / 1000.0) - 1.0;

        [objects addObject:object];
        index++;
    }
    return objects;
}

- (void)startAnimation
{
    [super startAnimation];
    _startDate = [NSDate date];

    // Now that we're attached to a window, derive a seed from the actual
    // physical screen so each monitor gets a distinct flight pattern.
    NSScreen *screen = self.window.screen;
    if (screen) {
        _screenSeed = [self seedFromScreenFrame:screen.frame];
        _objects = [self buildObjects]; // rebuild with the real screen seed
    }
}

- (void)stopAnimation
{
    [super stopAnimation];
}

- (void)drawRect:(NSRect)rect
{
    // Keep the pixel-art sprites crisp when scaled (e.g. in previews).
    [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationNone];
    [self drawScene];
}

/// Renders the full scene into the current graphics context.
- (void)drawScene
{
    NSTimeInterval elapsed = [self currentElapsed];
    NSSize size = self.bounds.size;

    [[NSColor blackColor] setFill];
    NSRectFill(self.bounds);

    // Sprites render at native 64pt (previously 50).
    CGFloat spriteSize = kSpriteSize;

    // Flight is always the classic 45° diagonal: enter from the top-right
    // corner, exit bottom-left (matching the original CSS keyframes).
    const CGFloat s = M_SQRT1_2; // 1/√2 for a 45° unit step
    const NSPoint dir = NSMakePoint(-s, -s);

    // Travel distance covers the full diagonal plus the maximum scatter and
    // lane ranges plus sprite margins, so every object — however offset —
    // starts and ends completely off-screen.
    CGFloat diagonal = hypot(size.width, size.height);
    CGFloat scatterRange = diagonal * 0.30;      // scatter span along flight axis
    CGFloat laneRange = diagonal * 0.5;          // lateral span across entry corner
    CGFloat distance = diagonal + scatterRange + laneRange + spriteSize * 4.0;

    for (FTFlyingObject *object in _objects) {
        NSTimeInterval t = elapsed - object.delay;
        if (t < 0) { continue; } // waiting for its wave to start

        CGFloat progress = fmod(t, object.period) / object.period;
        CGFloat travelled = progress * distance;

        // Convert the CSS `right`/`top` fractions into a bottom-left-origin
        // STARTING point off the top-right corner. CSS `right: R%` places
        // the object's right edge R% of width from the screen's right edge;
        // `top: T%` places its top edge T% of height below the top. Negative
        // R/T push it beyond those edges (off-screen).
        CGFloat baseX = size.width  - object.anchor.x * size.width  - spriteSize;
        CGFloat baseY = size.height - object.anchor.y * size.height - spriteSize;

        // Lane shifts the start point laterally across the entry corner
        // (along the anti-diagonal), so objects enter at varying positions
        // along the top and right edges instead of a fixed line.
        CGFloat laneOffset = object.lane * laneRange;
        baseX += laneOffset * s;
        baseY -= laneOffset * s;

        // Scatter shifts the object's START anchor *back* along the flight
        // axis (further off-screen) by 0..scatterRange. Because the shift only
        // ever moves the start point away from the screen (never onto it), at
        // progress == 0 the object is always fully off-screen; it then floats
        // in. This staggers entry timing and separates same-speed objects.
        CGFloat backoff = (object.scatter + 1.0) * 0.5 * scatterRange; // 0..scatterRange
        CGFloat startX = baseX - dir.x * backoff;
        CGFloat startY = baseY - dir.y * backoff;

        NSPoint position = NSMakePoint(startX + dir.x * travelled,
                                       startY + dir.y * travelled);

        NSRect destRect = NSMakeRect(position.x, position.y, spriteSize, spriteSize);

        if (object.kind == FTObjectKindToaster) {
            NSInteger frame = [self flapFrameForElapsed:t reverse:object.flapReverse];
            NSRect srcRect = NSMakeRect(frame * kSpriteSize, 0, kSpriteSize, kSpriteSize);
            [_toasterSprite drawInRect:destRect
                              fromRect:srcRect
                             operation:NSCompositingOperationSourceOver
                              fraction:1.0];
        } else {
            [_toastImage drawInRect:destRect
                           fromRect:NSZeroRect
                          operation:NSCompositingOperationSourceOver
                           fraction:1.0];
        }
    }
}

/// Current flap frame index (0-3) for a toaster, replicating the CSS
/// `flap .2s steps(4) infinite alternate(-reverse)` animation.
- (NSInteger)flapFrameForElapsed:(NSTimeInterval)elapsed reverse:(BOOL)reverse
{
    // CSS: flap .2s steps(4) infinite alternate over the 4-frame sheet.
    // steps(4) shows frame n/4 of the 0→-256px background-position sweep,
    // i.e. frames 0,1,2,3 within one 0.2s cycle. `alternate` then plays the
    // next cycle backwards: 3,2,1,0. `alternate-reverse` starts backwards.
    static const NSInteger forward[4]  = {0, 1, 2, 3};
    static const NSInteger backward[4] = {3, 2, 1, 0};

    NSTimeInterval cyclePosition = fmod(elapsed, kFlapCycleDuration * 2.0);
    if (cyclePosition < 0) { cyclePosition = 0; }
    NSInteger step = (NSInteger)(cyclePosition / kFlapCycleDuration * kFlapFrameCount);
    step = MAX(0, MIN(step, kFlapFrameCount - 1));

    BOOL forwardHalf = (cyclePosition < kFlapCycleDuration);
    // alternate:        forward half -> forward,  alternate half -> backward
    // alternate-reverse: forward half -> backward, alternate half -> forward
    BOOL useForward = reverse ? !forwardHalf : forwardHalf;
    return useForward ? forward[step] : backward[step];
}

- (void)animateOneFrame
{
    // Advance the clock and request a redraw. All drawing happens in
    // drawRect: (via drawScene) so AppKit flushes it to the screen.
    [self setNeedsDisplay:YES];
}

- (BOOL)hasConfigureSheet
{
    return NO;
}

- (NSWindow*)configureSheet
{
    return nil;
}

@end
