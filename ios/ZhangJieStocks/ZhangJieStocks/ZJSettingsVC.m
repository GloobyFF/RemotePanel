#import "ZJSettingsVC.h"
#import "ZJQuote.h"
#import "ZJStore.h"
#import "ZJTheme.h"

@interface ZJEditRow : NSObject
@property (nonatomic, copy) NSString *code;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) UITextField *buy;
@property (nonatomic, strong) UITextField *shares;
@end

@implementation ZJEditRow
@end

@interface ZJSettingsVC ()
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UITextField *sumField;
@property (nonatomic, strong) UITextField *stockField;
@property (nonatomic, strong) UITextField *addCode;
@property (nonatomic, strong) NSMutableArray<ZJEditRow *> *rows;
@property (nonatomic, assign) BOOL built;
@end

@implementation ZJSettingsVC

- (BOOL)prefersStatusBarHidden { return YES; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = ZJBG();
    self.rows = [NSMutableArray array];

    UILabel *title = ZJLabel(@"张洁股票", 28, UIFontWeightSemibold, ZJText());
    title.textAlignment = NSTextAlignmentLeft;
    title.frame = CGRectMake(24, 18, 280, 44);
    [self.view addSubview:title];

    UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem];
    [done setTitle:@"完成" forState:UIControlStateNormal];
    [done setTitleColor:ZJText() forState:UIControlStateNormal];
    done.titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightSemibold];
    done.frame = CGRectMake(self.view.bounds.size.width - 120, 16, 96, 48);
    done.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [done addTarget:self action:@selector(finish) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:done];

    self.scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.scroll];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.scroll.frame = CGRectMake(0, 72, self.view.bounds.size.width, self.view.bounds.size.height - 72);
    if (!self.built && self.view.bounds.size.width > 10) {
        self.built = YES;
        [self reloadForm];
    }
}

- (UITextField *)field:(NSString *)text placeholder:(NSString *)placeholder width:(CGFloat)width {
    UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, width, 44)];
    field.text = text;
    field.placeholder = placeholder;
    field.keyboardType = UIKeyboardTypeDecimalPad;
    field.textColor = ZJText();
    field.font = [UIFont monospacedDigitSystemFontOfSize:20 weight:UIFontWeightMedium];
    field.backgroundColor = ZJCard();
    field.layer.cornerRadius = 8;
    field.textAlignment = NSTextAlignmentCenter;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8, 44)];
    field.leftView = pad;
    field.leftViewMode = UITextFieldViewModeAlways;
    return field;
}

- (UILabel *)caption:(NSString *)text {
    UILabel *label = ZJLabel(text, 18, UIFontWeightMedium, ZJDim());
    label.textAlignment = NSTextAlignmentLeft;
    return label;
}

- (void)reloadForm {
    for (UIView *sub in [self.scroll.subviews copy]) [sub removeFromSuperview];
    [self.rows removeAllObjects];
    CGFloat W = self.view.bounds.size.width > 10 ? self.view.bounds.size.width : 1024;
    CGFloat x = 24;
    CGFloat y = 8;
    CGFloat rowW = W - 48;

    UILabel *dwellCap = [self caption:@"停留秒数    汇总页 / 每只股票"];
    dwellCap.frame = CGRectMake(x, y, rowW, 28);
    [self.scroll addSubview:dwellCap];
    y += 32;
    self.sumField = [self field:[NSString stringWithFormat:@"%ld", (long)[ZJStore dwellSummary]] placeholder:@"20" width:120];
    self.stockField = [self field:[NSString stringWithFormat:@"%ld", (long)[ZJStore dwellStock]] placeholder:@"12" width:120];
    self.sumField.frame = CGRectMake(x, y, 140, 44);
    self.stockField.frame = CGRectMake(x + 156, y, 140, 44);
    [self.scroll addSubview:self.sumField];
    [self.scroll addSubview:self.stockField];
    y += 64;

    UILabel *addCap = [self caption:@"添加股票代码，例如 600519"];
    addCap.frame = CGRectMake(x, y, rowW, 28);
    [self.scroll addSubview:addCap];
    y += 32;
    self.addCode = [self field:@"" placeholder:@"600519" width:200];
    self.addCode.keyboardType = UIKeyboardTypeNumberPad;
    self.addCode.frame = CGRectMake(x, y, 220, 44);
    [self.scroll addSubview:self.addCode];
    UIButton *add = [UIButton buttonWithType:UIButtonTypeSystem];
    [add setTitle:@"添加" forState:UIControlStateNormal];
    [add setTitleColor:ZJText() forState:UIControlStateNormal];
    add.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
    add.backgroundColor = ZJCard();
    add.layer.cornerRadius = 8;
    add.frame = CGRectMake(x + 236, y, 100, 44);
    [add addTarget:self action:@selector(addStock) forControlEvents:UIControlEventTouchUpInside];
    [self.scroll addSubview:add];
    y += 68;

    UILabel *listCap = [self caption:@"买入价和股数。股数留空就只显示每股赚多少。"];
    listCap.frame = CGRectMake(x, y, rowW, 28);
    [self.scroll addSubview:listCap];
    y += 36;

    for (ZJHolding *h in [ZJStore holdings]) {
        ZJEditRow *row = [[ZJEditRow alloc] init];
        row.code = h.code;
        row.name = h.name;
        UILabel *name = ZJLabel([NSString stringWithFormat:@"%@  %@", h.name.length ? h.name : h.code, h.code], 22, UIFontWeightSemibold, ZJText());
        name.textAlignment = NSTextAlignmentLeft;
        name.frame = CGRectMake(x, y, rowW - 80, 32);
        [self.scroll addSubview:name];
        UIButton *del = [UIButton buttonWithType:UIButtonTypeSystem];
        [del setTitle:@"删除" forState:UIControlStateNormal];
        [del setTitleColor:ZJUp() forState:UIControlStateNormal];
        del.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightMedium];
        del.frame = CGRectMake(x + rowW - 64, y, 64, 32);
        del.tag = (NSInteger)self.rows.count;
        [del addTarget:self action:@selector(deleteRow:) forControlEvents:UIControlEventTouchUpInside];
        [self.scroll addSubview:del];
        y += 36;
        row.buy = [self field:(h.buyPrice > 0 ? ZJGrouped(h.buyPrice) : @"") placeholder:@"买入价" width:180];
        row.shares = [self field:(h.shares > 0 ? ZJSharesText(h.shares) : @"") placeholder:@"股数" width:140];
        row.buy.frame = CGRectMake(x, y, 200, 44);
        row.shares.frame = CGRectMake(x + 216, y, 160, 44);
        [self.scroll addSubview:row.buy];
        [self.scroll addSubview:row.shares];
        [self.rows addObject:row];
        y += 60;
    }
    self.scroll.contentSize = CGSizeMake(W, y + 40);
}

- (double)numberFrom:(UITextField *)field {
    NSString *text = [field.text stringByReplacingOccurrencesOfString:@"," withString:@""];
    text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0) return 0;
    return [text doubleValue];
}

- (void)capture {
    NSInteger sum = (NSInteger)[self numberFrom:self.sumField];
    NSInteger stock = (NSInteger)[self numberFrom:self.stockField];
    [ZJStore setDwellSummary:sum > 0 ? sum : 20 stock:stock > 0 ? stock : 12];
    NSMutableArray<ZJHolding *> *holds = [NSMutableArray array];
    for (ZJEditRow *row in self.rows) {
        ZJHolding *h = [[ZJHolding alloc] init];
        h.code = row.code;
        h.name = row.name;
        h.buyPrice = [self numberFrom:row.buy];
        h.shares = [self numberFrom:row.shares];
        [holds addObject:h];
    }
    [ZJStore saveHoldings:holds];
}

- (void)addStock {
    [self capture];
    NSString *code = [ZJQuote codeForToken:self.addCode.text];
    if (code.length == 0) return;
    NSMutableArray<ZJHolding *> *holds = [[ZJStore holdings] mutableCopy];
    for (ZJHolding *h in holds) {
        if ([h.code isEqualToString:code]) {
            [self reloadForm];
            return;
        }
    }
    ZJHolding *h = [[ZJHolding alloc] init];
    h.code = code;
    h.name = code;
    [holds addObject:h];
    [ZJStore saveHoldings:holds];
    self.addCode.text = @"";
    [self reloadForm];
    [ZJQuote refreshNow:^(BOOL ok, NSString *error) {
        (void)ok; (void)error;
        [self reloadForm];
    }];
}

- (void)deleteRow:(UIButton *)button {
    [self capture];
    NSMutableArray<ZJHolding *> *holds = [[ZJStore holdings] mutableCopy];
    if (button.tag < 0 || button.tag >= (NSInteger)holds.count) return;
    [holds removeObjectAtIndex:(NSUInteger)button.tag];
    [ZJStore saveHoldings:holds];
    [self reloadForm];
}

- (void)finish {
    [self capture];
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
