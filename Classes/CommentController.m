#import "CommentController.h"
#import "NSString+Extensions.h"
#import "GHComment.h"


@implementation CommentController

@synthesize comment;
@synthesize comments;

- (id)initWithComment:(GHComment *)theComment andComments:(id)theComments {    
    [super initWithNibName:@"Comment" bundle:nil];
	
	self.comment = theComment;
	self.comments = theComments;
    [comment addObserver:self forKeyPath:kResourceSavingStatusKeyPath options:NSKeyValueObservingOptionNew context:nil];
	
	return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
	
	self.title = @"Post comment";
	self.navigationItem.rightBarButtonItem = postButton;
	
	[bodyView becomeFirstResponder];
}

- (void)dealloc {
	[comment removeObserver:self forKeyPath:kResourceSavingStatusKeyPath];
	[comment release], comment = nil;
	[comments release], comments = nil;
	[bodyView release], bodyView = nil;
	[postButton release], postButton = nil;
	[activityView release], activityView = nil;
	
    [super dealloc];
}

- (IBAction)postComment:(id)sender {
	comment.body = bodyView.text;
	
	// Validate
	if ([comment.body isEmpty]) {
		[[iOctocat sharedInstance] alert:@"Validation failed" with:@"Please enter a text"];
	} else {
		self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithCustomView:activityView] autorelease];
		[comment saveData];
	}
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if ([keyPath isEqualToString:kResourceSavingStatusKeyPath]) {
		if (comment.isSaving) return;
		if (comment.isSaved) {
			[[iOctocat sharedInstance] alert:@"Comment saved" with:@""];
			[comments loadData];
			[self.navigationController popViewControllerAnimated:YES];
		} else if (comment.error) {
			[[iOctocat sharedInstance] alert:@"Request error" with:@"Could not proceed the request"];
		}
		self.navigationItem.rightBarButtonItem = postButton;
	}
}

#pragma mark Autorotation

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation {
	return YES;
}

@end
