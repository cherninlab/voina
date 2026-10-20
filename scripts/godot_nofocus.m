// Injected into Godot by scripts/godot_bg.sh (macOS). Godot activates itself on launch, even through
// `open -g` and with display/window/size/no_focus, so parallel agent runs pop in front of whoever is
// typing and catch their keys (Esc opens the game menu mid-capture). This keeps the process from ever
// becoming the active app, hides it from the Dock and Cmd-Tab, and orders its windows behind all
// others. Covered windows keep rendering at full rate, so viewport captures are unaffected.
// VOINA_WINDOW_FRONT=1 leaves windows on top (still without focus) to watch a run.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

static BOOL (*set_policy)(id, SEL, NSInteger);

static void skip(id self, SEL cmd) {}
static void skip_flag(id self, SEL cmd, BOOL flag) {}
static BOOL skip_options(id self, SEL cmd, NSUInteger options) { return YES; }
static BOOL skip_from(id self, SEL cmd, id app, NSUInteger options) { return YES; }
static void order_back(id self, SEL cmd, id sender) { [self orderBack:sender]; }

static BOOL accessory_policy(id self, SEL cmd, NSInteger policy) {
	return set_policy(self, cmd, NSApplicationActivationPolicyAccessory);
}

static IMP replace(Class cls, SEL sel, IMP imp) {
	Method method = class_getInstanceMethod(cls, sel);
	return method ? method_setImplementation(method, imp) : NULL;
}

__attribute__((constructor)) static void godot_nofocus(void) {
	Class app = [NSApplication class];
	replace(app, @selector(activateIgnoringOtherApps:), (IMP)skip_flag);
	replace(app, @selector(activate), (IMP)skip);
	set_policy = (BOOL (*)(id, SEL, NSInteger))replace(app, @selector(setActivationPolicy:), (IMP)accessory_policy);
	Class running = [NSRunningApplication class];
	replace(running, @selector(activateWithOptions:), (IMP)skip_options);
	replace(running, @selector(activateFromApplication:options:), (IMP)skip_from);
	const char *front = getenv("VOINA_WINDOW_FRONT");
	if (!front || strcmp(front, "1") != 0) {
		Class window = [NSWindow class];
		replace(window, @selector(makeKeyAndOrderFront:), (IMP)order_back);
		replace(window, @selector(orderFront:), (IMP)order_back);
		replace(window, @selector(orderFrontRegardless), (IMP)skip);
	}
}
