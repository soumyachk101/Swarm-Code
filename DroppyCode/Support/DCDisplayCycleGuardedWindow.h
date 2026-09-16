#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// A window whose display-cycle requests survive being made from inside its own cycle.
///
/// Every window here shows SwiftUI under a transparent title bar (`fullSizeContentView`), so
/// after each layout AppKit works out the window's drag region by asking the hosting view for
/// its opaque content, and SwiftUI answers by evaluating the view graph. Whatever that
/// evaluation has pending runs right there, inside AppKit's "update structural regions" phase:
/// a scroll view moving to the offset a `scrollTo` asked for, a scroll geometry change
/// publishing a fresh transaction. Each of those ends in a view asking its window for another
/// display, layout or constraints pass, and on macOS 26 and 27 AppKit refuses that request with
/// an NSException instead of ignoring it, which ends the app (the Sept 16 2026 reports:
/// `_postWindowNeedsUpdateConstraints` under `NSHostingView.setNeedsUpdate`, and
/// `_postWindowNeedsDisplay` under `NSClipView _immediateScrollToPoint:`, both beneath
/// `-[NSWindow _resetDragMargins]`).
///
/// The request itself is sound; only its timing is not. This class catches the refusal at the
/// window, where every view's request arrives, and makes the same request again on the next
/// run loop turn, once the cycle is over. The view keeps its own dirty flag throughout, so
/// nothing is lost but a frame. Guarding one view's flags (the earlier fix, on the hosting
/// view) only moved the refusal to the next view down the chain, the scroll view's clip view.
@interface DCDisplayCycleGuardedWindow : NSWindow
@end

NS_ASSUME_NONNULL_END
