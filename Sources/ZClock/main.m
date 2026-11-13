#import <AppKit/AppKit.h>
#import <ServiceManagement/ServiceManagement.h>
#import <math.h>

static NSString *const ZClockTimeZoneKey = @"selectedTimeZoneID";
static NSString *const ZClockFormatKey = @"displayFormat";
static NSString *const ZClockDefaultFormat = @"M月d日 EEE h:mm:ss";

static NSString *ClockOffset(NSTimeZone *zone, NSDate *date) {
    NSInteger seconds = [zone secondsFromGMTForDate:date];
    NSInteger minutes = labs(seconds) / 60;
    return [NSString stringWithFormat:@"UTC%@%02ld:%02ld", seconds < 0 ? @"−" : @"+",
            (long)(minutes / 60), (long)(minutes % 60)];
}

@interface ZClockAppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate,
    NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate>
@end

@implementation ZClockAppDelegate {
    NSStatusItem *_statusItem;
    NSWindow *_settingsWindow;
    NSTextField *_formatField;
    NSTextField *_previewLabel;
    NSButton *_applyButton;
    NSButton *_loginCheckbox;
    NSTextField *_loginStatusLabel;
    NSError *_loginError;
    NSSearchField *_searchField;
    NSTableView *_tableView;
    NSArray<NSDictionary<NSString *, id> *> *_zones;
    NSArray<NSDictionary<NSString *, id> *> *_filteredZones;
    NSString *_selectedZoneID;
    NSString *_selectedFormat;
    NSString *_lastTitle;
    NSDateFormatter *_statusFormatter;
    NSTimer *_timer;
    id _keyMonitor;
}

- (NSTimeZone *)selectedZone {
    return [NSTimeZone timeZoneWithName:_selectedZoneID] ?: [NSTimeZone localTimeZone];
}

- (NSString *)formattedDate:(NSDate *)date dateStyle:(NSDateFormatterStyle)dateStyle {
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.timeZone = self.selectedZone;
    formatter.dateStyle = dateStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    return [formatter stringFromDate:date];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    NSString *savedZoneID = [[NSUserDefaults standardUserDefaults] stringForKey:ZClockTimeZoneKey];
    _selectedZoneID = [NSTimeZone timeZoneWithName:savedZoneID] ? savedZoneID : [NSTimeZone localTimeZone].name;
    NSString *savedFormat = [[NSUserDefaults standardUserDefaults] stringForKey:ZClockFormatKey];
    _selectedFormat = savedFormat.length > 0 ? savedFormat : ZClockDefaultFormat;
    _statusFormatter = [NSDateFormatter new];
    _statusFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    _statusFormatter.dateFormat = _selectedFormat;

    _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    NSMenu *menu = [NSMenu new];
    menu.delegate = self;
    _statusItem.menu = menu;
    [self refreshClock];

    NSMenu *mainMenu = [NSMenu new];
    NSMenuItem *windowMenuItem = [[NSMenuItem alloc] initWithTitle:@"窗口" action:nil keyEquivalent:@""];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"窗口"];
    NSMenuItem *closeItem = [[NSMenuItem alloc] initWithTitle:@"关闭设置窗口"
        action:@selector(closeSettings) keyEquivalent:@"w"];
    closeItem.target = self;
    [windowMenu addItem:closeItem];
    windowMenuItem.submenu = windowMenu;
    [mainMenu addItem:windowMenuItem];
    NSApp.mainMenu = mainMenu;

    _keyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
        handler:^NSEvent *(NSEvent *event) {
            NSEventModifierFlags modifiers = event.modifierFlags;
            BOOL commandOnly = (modifiers & NSEventModifierFlagCommand) != 0 &&
                (modifiers & (NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagShift)) == 0;
            if (self->_settingsWindow.isVisible && commandOnly &&
                [[event.charactersIgnoringModifiers lowercaseString] isEqualToString:@"w"]) {
                [self closeSettings];
                return nil;
            }
            return event;
        }];

    [self scheduleNextTick];
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
        selector:@selector(refreshClock) name:NSWorkspaceDidWakeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshLoginStatus)
        name:NSApplicationDidBecomeActiveNotification object:NSApp];
    if ([[NSProcessInfo processInfo].arguments containsObject:@"--show-settings"]) {
        [self performSelector:@selector(openSettings) withObject:nil afterDelay:0];
    }
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [_timer invalidate];
    if (_keyMonitor) [NSEvent removeMonitor:_keyMonitor];
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)closeSettings {
    if (_settingsWindow.isVisible) [_settingsWindow performClose:nil];
}

- (void)refreshClock {
    _statusFormatter.timeZone = self.selectedZone;
    NSString *title = [_statusFormatter stringFromDate:[NSDate date]];
    if (![_lastTitle isEqualToString:title]) {
        _statusItem.button.title = title;
        _lastTitle = title;
    }
    _statusItem.button.toolTip = [@"ZClock · " stringByAppendingString:_selectedZoneID];
}

- (void)updateFormatPreview {
    if (!_formatField) return;
    NSString *format = _formatField.stringValue;
    if ([format stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length == 0) {
        _previewLabel.stringValue = @"预览：请输入时间格式";
        _applyButton.enabled = NO;
        return;
    }
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    formatter.timeZone = self.selectedZone;
    formatter.dateFormat = format;
    NSString *preview = [formatter stringFromDate:[NSDate date]];
    _previewLabel.stringValue = preview.length > 0 ?
        [@"预览：" stringByAppendingString:preview] : @"预览：格式无法显示时间";
    _applyButton.enabled = preview.length > 0 && ![format isEqualToString:_selectedFormat];
}

- (void)applyFormat:(id)sender {
    if (!_applyButton.enabled) return;
    _selectedFormat = [_formatField.stringValue copy];
    [[NSUserDefaults standardUserDefaults] setObject:_selectedFormat forKey:ZClockFormatKey];
    _statusFormatter.dateFormat = _selectedFormat;
    [self refreshClock];
    [self updateFormatPreview];
}

- (void)resetFormat:(id)sender {
    _formatField.stringValue = ZClockDefaultFormat;
    [self updateFormatPreview];
    [self applyFormat:sender];
}

- (void)refreshLoginStatus {
    if (!_loginStatusLabel) return;
    SMAppServiceStatus status = SMAppService.mainAppService.status;
    switch (status) {
        case SMAppServiceStatusEnabled:
            _loginCheckbox.state = NSControlStateValueOn;
            _loginStatusLabel.stringValue = @"状态：已启用，系统允许登录时启动";
            _loginError = nil;
            break;
        case SMAppServiceStatusRequiresApproval:
            _loginCheckbox.state = NSControlStateValueOn;
            _loginStatusLabel.stringValue = @"状态：等待系统批准，请在登录项设置中允许 ZClock";
            break;
        case SMAppServiceStatusNotRegistered:
            _loginCheckbox.state = NSControlStateValueOff;
            _loginStatusLabel.stringValue = _loginError ?
                [@"状态：未启用 · " stringByAppendingString:_loginError.localizedDescription] : @"状态：未启用";
            break;
        case SMAppServiceStatusNotFound:
            _loginCheckbox.state = NSControlStateValueOff;
            _loginStatusLabel.stringValue = _loginError ?
                [@"状态：启用失败 · " stringByAppendingString:_loginError.localizedDescription] :
                @"状态：未启用（系统未找到登录项）";
            break;
    }
}

- (void)toggleLoginAtStartup:(NSButton *)sender {
    NSError *error = nil;
    SMAppService *service = SMAppService.mainAppService;
    if (sender.state == NSControlStateValueOn) {
        [service registerAndReturnError:&error];
    } else {
        [service unregisterAndReturnError:&error];
    }
    _loginError = error;
    [self refreshLoginStatus];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshLoginStatus) object:nil];
    [self performSelector:@selector(refreshLoginStatus) withObject:nil afterDelay:1];
}

- (void)openLoginItemsSettings:(id)sender {
    [SMAppService openSystemSettingsLoginItems];
}

- (void)scheduleNextTick {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSTimeInterval delay = ceil(now + 0.001) - now + 0.02;
    _timer = [NSTimer scheduledTimerWithTimeInterval:delay target:self
        selector:@selector(clockTick) userInfo:nil repeats:NO];
}

- (void)clockTick {
    [self refreshClock];
    [self scheduleNextTick];
}

- (void)menuWillOpen:(NSMenu *)menu {
    [self refreshClock];
    [menu removeAllItems];

    NSMenuItem *dateItem = [[NSMenuItem alloc] initWithTitle:
        [self formattedDate:[NSDate date] dateStyle:NSDateFormatterFullStyle]
        action:nil keyEquivalent:@""];
    dateItem.enabled = NO;
    [menu addItem:dateItem];

    NSMenuItem *zoneItem = [[NSMenuItem alloc] initWithTitle:
        [@"时区：" stringByAppendingString:_selectedZoneID] action:nil keyEquivalent:@""];
    zoneItem.enabled = NO;
    [menu addItem:zoneItem];
    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *chooseItem = [[NSMenuItem alloc] initWithTitle:@"设置…"
        action:@selector(openSettings) keyEquivalent:@","];
    chooseItem.target = self;
    [menu addItem:chooseItem];
    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"退出 ZClock"
        action:@selector(quit) keyEquivalent:@"q"];
    quitItem.target = self;
    [menu addItem:quitItem];
}

- (void)loadZones {
    if (_zones) return;
    NSDate *now = [NSDate date];
    NSMutableArray *zones = [NSMutableArray array];
    for (NSString *identifier in [NSTimeZone knownTimeZoneNames]) {
        NSTimeZone *zone = [NSTimeZone timeZoneWithName:identifier];
        NSString *city = [[identifier componentsSeparatedByString:@"/"] lastObject];
        city = [city stringByReplacingOccurrencesOfString:@"_" withString:@" "];
        [zones addObject:@{
            @"id": identifier,
            @"city": city,
            @"name": [zone localizedName:NSTimeZoneNameStyleStandard locale:[NSLocale currentLocale]] ?: @"",
            @"offset": ClockOffset(zone, now),
            @"seconds": @([zone secondsFromGMTForDate:now])
        }];
    }
    _zones = [zones sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSComparisonResult offsetOrder = [a[@"seconds"] compare:b[@"seconds"]];
        return offsetOrder == NSOrderedSame ? [a[@"id"] compare:b[@"id"]] : offsetOrder;
    }];
    _filteredZones = _zones;
}

- (void)openSettings {
    [self loadZones];
    if (!_settingsWindow) {
        _settingsWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 560, 780)
            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
            backing:NSBackingStoreBuffered defer:NO];
        _settingsWindow.releasedWhenClosed = NO;
        _settingsWindow.title = @"ZClock 设置";
        [_settingsWindow center];
        NSView *content = _settingsWindow.contentView;

        NSTextField *formatHeading = [NSTextField labelWithString:@"菜单栏时间格式"];
        formatHeading.font = [NSFont systemFontOfSize:20 weight:NSFontWeightSemibold];
        formatHeading.frame = NSMakeRect(20, 734, 520, 28);
        [content addSubview:formatHeading];

        NSTextField *formatHelp = [NSTextField labelWithString:@"输入日期格式字符串，预览确认后点击应用。"];
        formatHelp.textColor = [NSColor secondaryLabelColor];
        formatHelp.frame = NSMakeRect(20, 706, 520, 20);
        [content addSubview:formatHelp];

        _formatField = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 668, 520, 28)];
        _formatField.placeholderString = @"例如 yyyy-MM-dd HH:mm:ss";
        _formatField.stringValue = _selectedFormat;
        _formatField.delegate = self;
        [content addSubview:_formatField];

        NSTextField *examples = [NSTextField labelWithString:@"yyyy 年 · MM 月 · dd 日 · EEE 星期 · HH 24小时 · mm 分 · ss 秒"];
        examples.textColor = [NSColor secondaryLabelColor];
        examples.font = [NSFont systemFontOfSize:11];
        examples.frame = NSMakeRect(20, 640, 520, 18);
        [content addSubview:examples];

        _previewLabel = [NSTextField labelWithString:@""];
        _previewLabel.textColor = [NSColor secondaryLabelColor];
        _previewLabel.frame = NSMakeRect(20, 610, 520, 20);
        [content addSubview:_previewLabel];

        _applyButton = [NSButton buttonWithTitle:@"应用到菜单栏" target:self action:@selector(applyFormat:)];
        _applyButton.frame = NSMakeRect(410, 570, 130, 28);
        [content addSubview:_applyButton];
        NSButton *resetButton = [NSButton buttonWithTitle:@"恢复默认" target:self action:@selector(resetFormat:)];
        resetButton.frame = NSMakeRect(300, 570, 100, 28);
        [content addSubview:resetButton];

        NSBox *separator = [[NSBox alloc] initWithFrame:NSMakeRect(20, 552, 520, 1)];
        separator.boxType = NSBoxSeparator;
        [content addSubview:separator];

        NSTextField *loginHeading = [NSTextField labelWithString:@"登录时启动"];
        loginHeading.font = [NSFont systemFontOfSize:20 weight:NSFontWeightSemibold];
        loginHeading.frame = NSMakeRect(20, 516, 520, 28);
        [content addSubview:loginHeading];

        _loginCheckbox = [NSButton checkboxWithTitle:@"登录时启动 ZClock"
            target:self action:@selector(toggleLoginAtStartup:)];
        _loginCheckbox.frame = NSMakeRect(20, 482, 520, 24);
        [content addSubview:_loginCheckbox];

        _loginStatusLabel = [NSTextField labelWithString:@""];
        _loginStatusLabel.textColor = [NSColor secondaryLabelColor];
        _loginStatusLabel.frame = NSMakeRect(20, 454, 520, 20);
        [content addSubview:_loginStatusLabel];

        NSButton *loginSettingsButton = [NSButton buttonWithTitle:@"打开系统登录项设置"
            target:self action:@selector(openLoginItemsSettings:)];
        loginSettingsButton.frame = NSMakeRect(20, 420, 170, 28);
        [content addSubview:loginSettingsButton];
        NSButton *refreshLoginButton = [NSButton buttonWithTitle:@"重新检查"
            target:self action:@selector(refreshLoginStatus)];
        refreshLoginButton.frame = NSMakeRect(198, 420, 90, 28);
        [content addSubview:refreshLoginButton];

        NSBox *loginSeparator = [[NSBox alloc] initWithFrame:NSMakeRect(20, 408, 520, 1)];
        loginSeparator.boxType = NSBoxSeparator;
        [content addSubview:loginSeparator];

        NSTextField *zoneHeading = [NSTextField labelWithString:@"时区"];
        zoneHeading.font = [NSFont systemFontOfSize:20 weight:NSFontWeightSemibold];
        zoneHeading.frame = NSMakeRect(20, 372, 520, 28);
        [content addSubview:zoneHeading];

        _searchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(20, 332, 520, 28)];
        _searchField.placeholderString = @"搜索城市、地区或 UTC 偏移";
        _searchField.delegate = self;
        [content addSubview:_searchField];

        NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 20, 520, 300)];
        scrollView.hasVerticalScroller = YES;
        scrollView.borderType = NSBezelBorder;
        _tableView = [[NSTableView alloc] initWithFrame:scrollView.bounds];
        _tableView.headerView = nil;
        _tableView.rowHeight = 42;
        _tableView.delegate = self;
        _tableView.dataSource = self;
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"zone"];
        column.width = 500;
        [_tableView addTableColumn:column];
        scrollView.documentView = _tableView;
        [content addSubview:scrollView];
    }
    _formatField.stringValue = _selectedFormat;
    [self refreshClock];
    [self updateFormatPreview];
    [self refreshLoginStatus];
    [self selectCurrentZone];
    [_settingsWindow makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)selectCurrentZone {
    NSUInteger index = [_filteredZones indexOfObjectPassingTest:^BOOL(NSDictionary *zone, NSUInteger idx, BOOL *stop) {
        return [zone[@"id"] isEqualToString:self->_selectedZoneID];
    }];
    if (index != NSNotFound) {
        [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
        [_tableView scrollRowToVisible:index];
    }
}

- (void)controlTextDidChange:(NSNotification *)notification {
    if (notification.object == _formatField) {
        [self updateFormatPreview];
        return;
    }
    NSString *query = [_searchField.stringValue stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (query.length == 0) {
        _filteredZones = _zones;
    } else {
        _filteredZones = [_zones filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *zone, NSDictionary *bindings) {
            for (NSString *key in @[@"id", @"city", @"name", @"offset"]) {
                if ([zone[key] localizedStandardContainsString:query]) return YES;
            }
            return NO;
        }]];
    }
    [_tableView reloadData];
    if (query.length == 0) [self selectCurrentZone];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _filteredZones.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    static NSString *const cellID = @"ZoneCell";
    NSTableCellView *cell = [tableView makeViewWithIdentifier:cellID owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 420, 42)];
        cell.identifier = cellID;
        NSTextField *title = [NSTextField labelWithString:@""];
        title.frame = NSMakeRect(10, 20, 270, 18);
        title.autoresizingMask = NSViewWidthSizable;
        cell.textField = title;
        [cell addSubview:title];
        NSTextField *detail = [NSTextField labelWithString:@""];
        detail.tag = 100;
        detail.font = [NSFont systemFontOfSize:11];
        detail.textColor = [NSColor secondaryLabelColor];
        detail.frame = NSMakeRect(10, 3, 390, 16);
        detail.autoresizingMask = NSViewWidthSizable;
        [cell addSubview:detail];
    }
    NSDictionary *zone = _filteredZones[row];
    cell.textField.stringValue = [NSString stringWithFormat:@"%@   %@", zone[@"city"], zone[@"offset"]];
    ((NSTextField *)[cell viewWithTag:100]).stringValue = zone[@"id"];
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = _tableView.selectedRow;
    if (row < 0 || row >= _filteredZones.count) return;
    NSString *identifier = _filteredZones[row][@"id"];
    if ([identifier isEqualToString:_selectedZoneID]) return;
    _selectedZoneID = identifier;
    [[NSUserDefaults standardUserDefaults] setObject:identifier forKey:ZClockTimeZoneKey];
    [self refreshClock];
    [self updateFormatPreview];
}

- (void)quit {
    [NSApp terminate:nil];
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        ZClockAppDelegate *delegate = [ZClockAppDelegate new];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
