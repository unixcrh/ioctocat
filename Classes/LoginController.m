#import "LoginController.h"
#import "NSString+Extensions.h"
#import "GHUser.h"
#import "iOctocat.h"
#import "GradientButton.h"

@interface LoginController ()
+ (NSString *)stringFromUserDefaultsForKey:(NSString *)key defaultsTo:(NSString *)defaultValue;
- (void)presentLogin;
- (void)dismissLogin;
- (void)showAuthenticationSheet;
- (void)dismissAuthenticationSheet;
- (void)finishAuthenticating;
- (void)failWithMessage:(NSString *)theMessage;
- (void)resolveToken;
@end


@implementation LoginController

@synthesize loginField;
@synthesize passwordField;
@synthesize submitButton;
@synthesize delegate;
@synthesize user;

+ (NSString *)stringFromUserDefaultsForKey:(NSString *)key defaultsTo:(NSString *)defaultValue {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSString *value = [defaults stringForKey:key];
	return value != nil ? value : defaultValue;
}

- (id)initWithViewController:(UIViewController *)theViewController {
	[super initWithNibName:@"Login" bundle:nil];
    viewController = theViewController;
	return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    loginField.text = [LoginController stringFromUserDefaultsForKey:kLoginDefaultsKey defaultsTo:@""];
    passwordField.text = [LoginController stringFromUserDefaultsForKey:kPasswordDefaultsKey defaultsTo:@""];
    [submitButton useAlertStyle];
}

- (void)dealloc {
    [loginField release], loginField = nil;
    [passwordField release], passwordField = nil;
    [submitButton release], submitButton = nil;
    [authSheet release], authSheet = nil;
    [super dealloc];
}

- (void)failWithMessage:(NSString *)theMessage {
	[[iOctocat sharedInstance] alert:@"Authentication failed" with:theMessage];
	submitButton.enabled = YES;
}

- (IBAction)submit:(id)sender {
	NSCharacterSet *trimSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];
	NSString *login = [loginField.text stringByTrimmingCharactersInSet:trimSet];
	NSString *password = [passwordField.text stringByTrimmingCharactersInSet:trimSet];
	if ([login isEmpty] || [password isEmpty]) {
		[self failWithMessage:@"Please enter your login\nand password"];
	} else {
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		[defaults setValue:login forKey:kLoginDefaultsKey];
		[defaults setValue:password forKey:kPasswordDefaultsKey];
		[defaults synchronize];
		submitButton.enabled = NO;
        self.user = [[iOctocat sharedInstance] currentUser];
		[loginField resignFirstResponder];
		[passwordField resignFirstResponder];
		[self startAuthenticating];
	}
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
	[loginField resignFirstResponder];
	[passwordField resignFirstResponder];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	[textField resignFirstResponder];
	if (textField == loginField) [passwordField becomeFirstResponder];
    if (textField == passwordField) [self submit:nil];
	return YES;
}

- (void)startAuthenticating {
    if (!self.user) {
		[self presentLogin];
	} else {
        [self.user addObserver:self forKeyPath:kResourceLoadingStatusKeyPath options:NSKeyValueObservingOptionNew context:nil];
		[self.user loadData];
	}
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if (self.user.isLoading) {
		[self showAuthenticationSheet];
	} else {
        [self.user removeObserver:self forKeyPath:kResourceLoadingStatusKeyPath];
        [self dismissAuthenticationSheet];
        if (self.user.isAuthenticated) {
            [self finishAuthenticating];
        } else {
            [self presentLogin];
            [self failWithMessage:@"Please ensure that you are connected to the internet and that your login and password are correct"];
        }
    }
}

- (void)stopAuthenticating {
    submitButton.enabled = YES;
    [self dismissAuthenticationSheet];
}

- (void)finishAuthenticating {
    [self dismissLogin];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *token = [defaults stringForKey:kTokenDefaultsKey];
    if ([token length] < 32) [self resolveToken];

    if ([delegate respondsToSelector:@selector(finishedAuthenticating)]) {
        [delegate performSelector:@selector(finishedAuthenticating) withObject:self.user];
    }
}

- (void)presentLogin {
  if (viewController.modalViewController == self) return;
  self.modalPresentationStyle = UIModalPresentationFormSheet;
  [viewController presentModalViewController:self animated:YES];
}

- (void)dismissLogin {
	if (viewController.modalViewController != self) return;
	[viewController dismissModalViewControllerAnimated:YES];
}

- (void)showAuthenticationSheet {
	authSheet = [[UIActionSheet alloc] initWithTitle:@"\nAuthenticating, please wait…\n\n" delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
	UIView *currentView = viewController.modalViewController ? viewController.modalViewController.view : viewController.view;
	[authSheet showInView:currentView];
}

- (void)dismissAuthenticationSheet {
	[authSheet dismissWithClickedButtonIndex:0 animated:YES];
	[authSheet release], authSheet = nil;
}

#pragma mark Lookup API Token

- (void)resolveToken {
    UIWebView *webView = [[UIWebView alloc] init];
    NSURL *url = [NSURL URLWithString:@"https://github.com/login"];
    NSURLRequest *requestObj = [NSURLRequest requestWithURL:url];
    webView.delegate = self;
    [webView loadRequest:requestObj];
}

- (void)webViewDidFinishLoad:(UIWebView *)webView {
    if ([[[webView.request URL] path] isEqualToString:@"/login"]) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSString *login = [defaults stringForKey:kLoginDefaultsKey];
        NSString *password = [defaults stringForKey:kPasswordDefaultsKey];
        NSString *js = [NSString stringWithFormat:@"$('#login_field').val('%@');$('#password').val('%@');$('#login_field')[0].form.submit()", login, password];
        [webView stringByEvaluatingJavaScriptFromString:js];
    } else if ([[[webView.request URL] path] isEqualToString:@"/"]) {
        NSString *token = [webView stringByEvaluatingJavaScriptFromString:@"$('a.feed')[0].href.match(/token=(.*)/)[1]"];
        if (![token isEqualToString:@""]) {
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            [defaults setValue:token forKey:kTokenDefaultsKey];
            [defaults synchronize];
            [webView release];
        }
    }
}

#pragma mark Autorotation

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation {
	return YES;
}

@end
