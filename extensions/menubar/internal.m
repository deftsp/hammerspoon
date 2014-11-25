#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <lauxlib.h>

#define USERDATA_TAG "hs.menubar"

@interface clickDelegate : NSObject
@property lua_State *L;
@property int fn;
@end

@implementation clickDelegate
- (void) click:(id)sender {
    NSLog(@"clicked");
}
@end

static int store_udhandler(lua_State *L, NSMutableIndexSet *theHandler, int idx) {
    lua_pushvalue(L, idx);
    int x = luaL_ref(L, LUA_REGISTRYINDEX);
    [theHandler addIndex: x];
    return x;
}

static void remove_udhandler (lua_State *L, NSMutableIndexSet *theHandler, int x) {
    luaL_unref(L, LUA_REGISTRYINDEX, x);
    [theHandler removeIndex: x];
}

static NSMutableIndexSet *menuBarItemHandlers;

typedef struct _menubaritem_t {
    void *menuBarItemObject;
    void *click_callback;
    int click_fn;
    int registryHandle;
} menubaritem_t;

/// hs.menubar.new(icon, text) -> menubaritem
/// Constructor
/// Creates a new menu bar item object, which can be added to the system menubar by calling menubaritem:add()
///
/// icon argument is the path to an image file that will be loaded and used for the menu
/// text argument is a string to use in place of an icon
///
/// Note: You must provide either an icon or some text, and nil for the other. If you provide both, the icon will win
static int menubar_new(lua_State *L) {
    NSStatusBar *statusBar = [NSStatusBar systemStatusBar];
    NSStatusItem *statusItem = [statusBar statusItemWithLength:NSVariableStatusItemLength];

    if (statusItem) {
        menubaritem_t *menuBarItem = lua_newuserdata(L, sizeof(menubaritem_t));
        memset(menuBarItem, 0, sizeof(menubaritem_t));
        menuBarItem->menuBarItemObject = (__bridge_retained void*)statusItem;
        menuBarItem->click_callback = nil;
        menuBarItem->click_fn = 0;
        menuBarItem->registryHandle = store_udhandler(L, menuBarItemHandlers, -1);
        luaL_getmetatable(L, USERDATA_TAG);
        lua_setmetatable(L, -2);
    } else {
        lua_pushnil(L);
    }

    return 1;
}

/// hs.menubar:setTitle(title)
/// Method
/// Sets the text on a menubar item. If an icon is also set, this text will be displayed next to the icon
static int menubar_settitle(lua_State *L) {
    menubaritem_t *menuBarItem = luaL_checkudata(L, 1, USERDATA_TAG);
    NSString *titleText = [NSString stringWithUTF8String:luaL_checkstring(L, 2)];
    lua_settop(L, 1);
    [(__bridge NSStatusItem*)menuBarItem->menuBarItemObject setTitle:titleText];

    return 0;
}

/// hs.menubar:setIcon(iconfilepath) -> bool
/// Method
/// Loads the image specified by iconfilepath and sets it as the menu bar item's icon
static int menubar_seticon(lua_State *L) {
    menubaritem_t *menuBarItem = luaL_checkudata(L, 1, USERDATA_TAG);
    NSImage *iconImage = [[NSImage alloc] initWithContentsOfFile:[NSString stringWithUTF8String:luaL_checkstring(L, 2)]];
    lua_settop(L, 1);
    if (!iconImage) {
        lua_pushnil(L);
        return 1;
    }
    [iconImage setTemplate:YES];
    [(__bridge NSStatusItem*)menuBarItem->menuBarItemObject setImage:iconImage];

    lua_pushboolean(L, 1);
    return 1;
}

/// hs.menubar:setTooltip(tooltip)
/// Method
/// Sets the tooltip text on a menubar item.
static int menubar_settooltip(lua_State *L) {
    menubaritem_t *menuBarItem = luaL_checkudata(L, 1, USERDATA_TAG);
    NSString *toolTipText = [NSString stringWithUTF8String:luaL_checkstring(L, 2)];
    lua_settop(L, 1);
    [(__bridge NSStatusItem*)menuBarItem->menuBarItemObject setToolTip:toolTipText];

    return 0;
}

/// hs.menubar:clickCallback(fn)
/// Method
/// Registers a function to be called when the menubar icon is clicked. If the argument is nil, the previously registered callback is removed.
// FIXME: Document that this makes no sense when a menu is being used, when we have menu support
static int menubar_click_callback(lua_State *L) {
    menubaritem_t *menuBarItem = luaL_checkudata(L, 1, USERDATA_TAG);
    NSStatusItem *statusItem = (__bridge NSStatusItem*)menuBarItem->menuBarItemObject;
    if (lua_isnil(L, 2)) {
        if (menuBarItem->click_fn) {
            luaL_unref(L, LUA_REGISTRYINDEX, menuBarItem->click_fn);
            menuBarItem->click_fn = 0;
        }
        if (menuBarItem->click_callback) {
            [statusItem setTarget:nil];
            [statusItem setAction:nil];
            clickDelegate *object = (__bridge_transfer clickDelegate *)menuBarItem->click_callback;
            menuBarItem->click_callback = nil;
            object = nil;
        }
    } else {
        luaL_checktype(L, 2, LUA_TFUNCTION);
        lua_pushvalue(L, 2);
        menuBarItem->click_fn = luaL_ref(L, LUA_REGISTRYINDEX);
        clickDelegate *object = [[clickDelegate alloc] init];
        object.L = L;
        object.fn = menuBarItem->click_fn;
        menuBarItem->click_callback = (__bridge_retained void*) object;
        [statusItem setTarget:object];
        [statusItem setAction:@selector(click:)];
    }
    return 0;
}

/// hs.menubar:addMenu(items)
/// Method
/// Adds a menu to the menubar item with the supplied items in it, in the form:
///  { ["name"] = fn }
static int menubar_add_menu(lua_State *L) {
    menubaritem_t *menuBarItem = luaL_checkudata(L, 1, USERDATA_TAG);
    NSStatusItem *statusItem = (__bridge NSStatusItem*)menuBarItem->menuBarItemObject;
    luaL_checktype(L, 2, LUA_TTABLE);

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"HammerspoonMenuItemMenu"];
    lua_pushnil(L);
    while (lua_next(L, 2) != 0) {
        NSString *menuItemTitle = [NSString stringWithUTF8String:lua_tostring(L, -2)];
        NSLog(@"Adding a menu item with title: %@", menuItemTitle);
        // FIXME: How do we store all the callbacks?
        NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:menuItemTitle action:nil keyEquivalent:@""];
        [menuItem setState:NSOnState];
        [menu addItem:menuItem];
        lua_pop(L, 1);
    }

    if ([menu numberOfItems] > 0) {
        NSLog(@"got menu items, adding menu");
        [statusItem setMenu:menu];
    } else {
        NSLog(@"no menu items, discarding menu");
    }

    return 0;
}

/// hs.menubar:removeMenu()
/// Method
/// Removes the menu previously associated with a menubar item
static int menubar_remove_menu(lua_State *L) {
    menubaritem_t *menuBarItem = luaL_checkudata(L, 1, USERDATA_TAG);
    NSStatusItem *statusItem = (__bridge NSStatusItem*)menuBarItem->menuBarItemObject;
    // FIXME: Remove handlers here too
    [statusItem setMenu:nil];

    return 0;
}

/// hs.menubar:delete(menubaritem)
/// Method
/// Removes the menubar item from the menubar and destroys it
static int menubar_delete(lua_State *L) {
    NSStatusBar *statusBar = [NSStatusBar systemStatusBar];
    menubaritem_t *menuBarItem = luaL_checkudata(L, 1, USERDATA_TAG);

    // FIXME: We probably need to release other things here? like remove the callbacks and suchlike?

    remove_udhandler(L, menuBarItemHandlers, menuBarItem->registryHandle);
    [statusBar removeStatusItem:(__bridge NSStatusItem*)menuBarItem->menuBarItemObject];
    menuBarItem->menuBarItemObject = nil;
    menuBarItem = nil;

    return 0;
}

// ----------------------- Lua/hs glue GAR ---------------------

static int menubar_setup(lua_State* __unused L) {
    if (!menuBarItemHandlers) menuBarItemHandlers = [NSMutableIndexSet indexSet];
    return 0;
}

static int meta_gc(lua_State* __unused L) {
    [menuBarItemHandlers removeAllIndexes];
    menuBarItemHandlers = nil;
    return 0;
}

static int menubar_gc(lua_State *L) {
    NSLog(@"menubar_gc");

    // FIXME: This is almost certainly wrong, we need to remove all of the menubar items
    menubar_delete(L);
    return 0;
}

static const luaL_Reg menubarlib[] = {
    {"new", menubar_new},

    {"__gc", menubar_gc},
    {}
};

static const luaL_Reg menubar_metalib[] = {
    {"setTitle", menubar_settitle},
    {"setIcon", menubar_seticon},
    {"setTooltip", menubar_settooltip},
    {"clickCallback", menubar_click_callback},
    {"addMenu", menubar_add_menu},
    {"removeMenu", menubar_remove_menu},
    {"delete", menubar_delete},

    {}
};

static const luaL_Reg meta_gclib[] = {
    {"__gc", meta_gc},

    {}
};

/* NOTE: The substring "hs_menubar_internal" in the following function's name
         must match the require-path of this file, i.e. "hs.menubar.internal". */

int luaopen_hs_menubar_internal(lua_State *L) {
    menubar_setup(L);

    // Metatable for created objects
    luaL_newlib(L, menubar_metalib);
    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");
    lua_setfield(L, LUA_REGISTRYINDEX, USERDATA_TAG);

    // Table for luaopen
    luaL_newlib(L, menubarlib);
    luaL_newlib(L, meta_gclib);
    lua_setmetatable(L, -2);

    return 1;
}
