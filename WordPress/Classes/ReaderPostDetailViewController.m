//
//  ReaderPostDetailViewController.m
//  WordPress
//
//  Created by Eric J on 3/21/13.
//  Copyright (c) 2013 WordPress. All rights reserved.
//

#import "ReaderPostDetailViewController.h"
#import <DTCoreText/DTCoreText.h>
#import <QuartzCore/QuartzCore.h>
#import <MessageUI/MFMailComposeViewController.h>
#import "UIImageView+Gravatar.h"
#import "WPActivities.h"
#import "WPWebViewController.h"
#import "PanelNavigationConstants.h"
#import "WordPressAppDelegate.h"
#import "WordPressComApi.h"
#import "ReaderComment.h"
#import "ReaderCommentTableViewCell.h"
#import "ReaderPostDetailView.h"
#import "ReaderCommentFormView.h"
#import "ReaderReblogFormView.h"

NSInteger const ReaderCommentsToSync = 100;

@interface ReaderPostDetailViewController ()<ReaderPostDetailViewDelegate, UIActionSheetDelegate, MFMailComposeViewControllerDelegate, ReaderTextFormDelegate> {
	BOOL _hasMoreContent;
	BOOL _loadingMore;
    CGFloat _previousOffset;
}

@property (nonatomic, strong) ReaderPost *post;
@property (nonatomic, strong) ReaderPostDetailView *headerView;
@property (nonatomic, strong) ReaderCommentFormView *readerCommentFormView;
@property (nonatomic, strong) ReaderReblogFormView *readerReblogFormView;
@property (nonatomic, strong) UINavigationBar *navBar;
@property (nonatomic, strong) UIBarButtonItem *commentButton;
@property (nonatomic, strong) UIBarButtonItem *likeButton;
@property (nonatomic, strong) UIBarButtonItem *reblogButton;
@property (nonatomic, strong) UIBarButtonItem *shareButton;
@property (nonatomic, strong) UIActionSheet *linkOptionsActionSheet;
@property (nonatomic, strong) NSMutableArray *comments;
@property (nonatomic, strong) NSFetchedResultsController *resultsController;
@property (nonatomic) BOOL isScrollingCommentIntoView;
@property (nonatomic) BOOL isShowingCommentForm;
@property (nonatomic) BOOL isShowingReblogForm;

- (void)buildHeader;
- (void)buildTopToolbar;
- (void)buildBottomToolbar;
- (void)buildForms;
- (void)prepareComments;
- (void)showStoredComment;
- (void)updateToolbar;
- (BOOL)isReplying;
- (BOOL)canComment;
- (void)showCommentForm;
- (void)hideCommentForm;
- (void)showReblogForm;
- (void)hideReblogForm;

- (void)handleCommentButtonTapped:(id)sender;
- (void)handleLikeButtonTapped:(id)sender;
- (void)handleReblogButtonTapped:(id)sender;
- (void)handleShareButtonTapped:(id)sender;
- (void)handleCloseKeyboard:(id)sender;
- (BOOL)setMFMailFieldAsFirstResponder:(UIView*)view mfMailField:(NSString*)field;

@end

@implementation ReaderPostDetailViewController

@synthesize post;

#pragma mark - LifeCycle Methods

- (void)dealloc {
	_resultsController.delegate = nil;
}


- (id)initWithPost:(ReaderPost *)apost {
	self = [super init];
	if(self) {
		self.post = apost;
		self.comments = [NSMutableArray array];
        self.wantsFullScreenLayout = YES;
	}
	return self;
}


- (id)initWithDictionary:(NSDictionary *)dict {
	self = [super init];
	if(self) {
		// TODO: for supporting Twitter cards.
	}
	return self;
}


- (void)viewDidLoad {
	[super viewDidLoad];

	self.title = self.post.postTitle;
	
	self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.contentInset = UIEdgeInsetsMake(self.navigationController.navigationBar.frame.size.height, 0, self.navigationController.toolbar.frame.size.height, 0);
	
	if ([self.resultsController.fetchedObjects count] > 0) {
		self.tableView.backgroundColor = [UIColor colorWithHexString:@"EFEFEF"];
	}
	
	[self buildHeader];
	[self buildTopToolbar];
	[self buildBottomToolbar];
	[self buildForms];
	
	[self prepareComments];
	[self showStoredComment];

}


- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	
	self.panelNavigationController.delegate = self;
    [self setFullScreen:NO];
    [self.navigationController setNavigationBarHidden:NO animated:YES];
    self.navigationController.navigationBar.translucent = YES;
    self.navigationController.toolbar.translucent = YES;

	UIToolbar *toolbar = self.navigationController.toolbar;
	[toolbar setBackgroundImage:nil forToolbarPosition:UIToolbarPositionBottom barMetrics:UIBarMetricsDefault];
	[toolbar setTintColor:[UIColor colorWithHexString:@"F1F1F1"]];
	
	if (IS_IPAD)
        [self.panelNavigationController setToolbarHidden:NO forViewController:self animated:NO];

	[_headerView updateLayout];
	[self showStoredComment];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
	
    self.panelNavigationController.delegate = nil;
    self.navigationController.navigationBar.translucent = NO;
    self.navigationController.toolbar.translucent = NO;
    [self.navigationController setNavigationBarHidden:NO animated:YES];
	[self.navigationController setToolbarHidden:YES animated:YES];
}

- (void)viewDidUnload {
	[super viewDidUnload];
    
	self.headerView = nil;
	self.readerCommentFormView = nil;
	self.readerReblogFormView = nil;
	self.navBar = nil;
	self.commentButton = nil;
	self.likeButton = nil;
	self.reblogButton = nil;
	self.shareButton = nil;
	
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return [super shouldAutorotateToInterfaceOrientation:interfaceOrientation];
}


- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
	[super willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
}


- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
	[super didRotateFromInterfaceOrientation:fromInterfaceOrientation];

	[_headerView updateLayout];
}


#pragma mark - Instance Methods

- (void)buildHeader{
	self.headerView = [[ReaderPostDetailView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, self.tableView.frame.size.width, 190.0f) post:self.post delegate:self];
	_headerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	_headerView.backgroundColor = [UIColor whiteColor];
	[self.tableView setTableHeaderView:_headerView];
	
	UITapGestureRecognizer *tgr = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleCloseKeyboard:)];
	tgr.cancelsTouchesInView = NO;
	[_headerView addGestureRecognizer:tgr];
}


- (void)buildTopToolbar {
	// Top Navigation bar and Sharing.
	if ([[UIButton class] respondsToSelector:@selector(appearance)]) {
		UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
		
		[btn setImage:[UIImage imageNamed:@"navbar_actions.png"] forState:UIControlStateNormal];
		[btn setImage:[UIImage imageNamed:@"navbar_actions.png"] forState:UIControlStateHighlighted];
		
		UIImage *backgroundImage = [[UIImage imageNamed:@"navbar_button_bg"] stretchableImageWithLeftCapWidth:4 topCapHeight:0];
		[btn setBackgroundImage:backgroundImage forState:UIControlStateNormal];
		
		backgroundImage = [[UIImage imageNamed:@"navbar_button_bg_active"] stretchableImageWithLeftCapWidth:4 topCapHeight:0];
		[btn setBackgroundImage:backgroundImage forState:UIControlStateHighlighted];
		btn.frame = CGRectMake(0.0f, 0.0f, 44.0f, 30.0f);
		[btn addTarget:self action:@selector(handleShareButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
		
		self.shareButton = [[UIBarButtonItem alloc] initWithCustomView:btn];
	} else {
		self.shareButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
																		 target:self
																		 action:@selector(handleShareButtonTapped:)];
	}
	
	self.navigationItem.rightBarButtonItem = _shareButton;
	
	if(IS_IPAD) {
		
		self.navBar = [[UINavigationBar alloc] initWithFrame:CGRectMake(0.0f, 0.0f, self.view.frame.size.width, 44.0f)];
		_navBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[_navBar pushNavigationItem:self.navigationItem animated:NO];
		[self.view addSubview:_navBar];
		
		CGRect frame = self.tableView.frame;
		frame.origin.y = 44.0f;
		frame.size.height -= 44.0f;
		self.tableView.frame = frame;
	}

}


- (void)buildBottomToolbar {
	
	UIButton *commentBtn = [UIButton buttonWithType:UIButtonTypeCustom];
	[commentBtn setImage:[UIImage imageNamed:@"reader-postaction-comment"] forState:UIControlStateNormal];
    [commentBtn setImage:[UIImage imageNamed:@"reader-postaction-comment-active"] forState:UIControlStateHighlighted];
	commentBtn.frame = CGRectMake(0.0f, 0.0f, 40.0f, 40.0f);
	[commentBtn addTarget:self action:@selector(handleCommentButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
	self.commentButton = [[UIBarButtonItem alloc] initWithCustomView:commentBtn];
	
	UIButton *likeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
	[likeBtn.titleLabel setFont:[UIFont fontWithName:@"OpenSans-Bold" size:10.0f]];
	[likeBtn setTitleEdgeInsets:UIEdgeInsetsMake(0.0f, -5.0f, 0.0f, 0.0f)];
	[likeBtn setTitleColor:[UIColor colorWithRed:84.0f/255.0f green:173.0f/255.0f blue:211.0f/255.0f alpha:1.0f] forState:UIControlStateNormal];
	[likeBtn setTitleColor:[UIColor colorWithRed:221.0f/255.0f green:118.0f/255.0f blue:43.0f/255.0f alpha:1.0f] forState:UIControlStateSelected];
	[likeBtn setImage:[UIImage imageNamed:@"reader-postaction-like"] forState:UIControlStateNormal];
    [likeBtn setImage:[UIImage imageNamed:@"reader-postaction-like-active"] forState:UIControlStateSelected];
	likeBtn.frame = CGRectMake(0.0f, 0.0f, 60.0f, 40.0f);
	likeBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
	[likeBtn addTarget:self action:@selector(handleLikeButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
	self.likeButton = [[UIBarButtonItem alloc] initWithCustomView:likeBtn];
	
	UIButton *reblogBtn = [UIButton buttonWithType:UIButtonTypeCustom];
	[reblogBtn setImage:[UIImage imageNamed:@"reader-postaction-reblog"] forState:UIControlStateNormal];
    [reblogBtn setImage:[UIImage imageNamed:@"reader-postaction-reblog-active"] forState:UIControlStateSelected];
	reblogBtn.frame = CGRectMake(0.0f, 0.0f, 40.0f, 40.0f);
	reblogBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	[reblogBtn addTarget:self action:@selector(handleReblogButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
	self.reblogButton = [[UIBarButtonItem alloc] initWithCustomView:reblogBtn];
	
	[self updateToolbar];
}


- (void)buildForms {
	CGRect frame = CGRectMake(0.0f, self.tableView.frame.origin.y + self.tableView.bounds.size.height, self.view.bounds.size.width, [ReaderCommentFormView desiredHeight]);
	self.readerCommentFormView = [[ReaderCommentFormView alloc] initWithFrame:frame];
	_readerCommentFormView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
	_readerCommentFormView.navigationItem = self.navigationItem;
	_readerCommentFormView.post = self.post;
	_readerCommentFormView.delegate = self;
	
	if (_isShowingCommentForm) {
		[self showCommentForm];
	}
	
	frame = CGRectMake(0.0f, self.view.bounds.size.height, self.view.bounds.size.width, [ReaderReblogFormView desiredHeight]);
	self.readerReblogFormView = [[ReaderReblogFormView alloc] initWithFrame:frame];
	_readerReblogFormView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
	_readerReblogFormView.navigationItem = self.navigationItem;
	_readerReblogFormView.post = self.post;
	_readerReblogFormView.delegate = self;
	
	if (_isShowingReblogForm) {
		[self showReblogForm];
	}
}


- (BOOL)canComment {
	return [self.post.commentsOpen boolValue];
}


- (void)prepareComments {
	self.resultsController = nil;
	[_comments removeAllObjects];
	
	__block void(__unsafe_unretained ^flattenComments)(NSArray *) = ^void (NSArray *comments) {
		// Ensure the array is correctly sorted. 
		comments = [comments sortedArrayUsingComparator: ^(id obj1, id obj2) {
			ReaderComment *a = obj1;
			ReaderComment *b = obj2;
			if ([[a dateCreated] timeIntervalSince1970] > [[b dateCreated] timeIntervalSince1970]) {
				return (NSComparisonResult)NSOrderedDescending;
			}
			if ([[a dateCreated] timeIntervalSince1970] < [[b dateCreated] timeIntervalSince1970]) {
				return (NSComparisonResult)NSOrderedAscending;
			}
			return (NSComparisonResult)NSOrderedSame;
		}];
		
		for (ReaderComment *comment in comments) {
			[_comments addObject:comment];
			if([comment.childComments count] > 0) {
				flattenComments([comment.childComments allObjects]);
			}
		}
	};
	
	flattenComments(self.resultsController.fetchedObjects);
}


- (void)updateToolbar {
	if (!self.post) return;
	
	UIButton *btn = (UIButton *)_likeButton.customView;
	[btn setSelected:[self.post.isLiked boolValue]];
	NSString *str = ([self.post.likeCount integerValue] > 0) ? [self.post.likeCount stringValue] : nil;
	[btn setTitle:str forState:UIControlStateNormal];
	_likeButton.customView = btn;
	
	btn = (UIButton *)_reblogButton.customView;
	[btn setSelected:[self.post.isReblogged boolValue]];
	_reblogButton.customView = btn;
	
	UIBarButtonItem *placeholder = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
	NSMutableArray *items = [NSMutableArray arrayWithObject:placeholder];
	if ([self canComment]) {
		[items addObjectsFromArray:@[_commentButton, placeholder]];
	}
	
	if ([self.post isWPCom]) {
		[items addObjectsFromArray:@[_likeButton, placeholder, _reblogButton]];
	}
	
	[items addObject:placeholder];
	
	[self setToolbarItems:items animated:YES];
	
	self.navigationController.toolbarHidden = NO;
}


- (void)handleCommentButtonTapped:(id)sender {
	if (_readerCommentFormView.window != nil) {
		[self hideCommentForm];
		return;
	}
	
	[self showCommentForm];
}

- (void)handleLikeButtonTapped:(id)sender {
	[self.post toggleLikedWithSuccess:^{
		
	} failure:^(NSError *error) {
		WPLog(@"Error Liking Post : %@", [error localizedDescription]);
		[self updateToolbar];
	}];
	[self updateToolbar];
}


- (void)handleReblogButtonTapped:(id)sender {
	if (_isShowingReblogForm) {
		[self hideReblogForm];
		return;
	}
	
	[self showReblogForm];
}


- (void)handleShareButtonTapped:(id)sender {
	
	if (self.linkOptionsActionSheet) {
        [self.linkOptionsActionSheet dismissWithClickedButtonIndex:-1 animated:NO];
        self.linkOptionsActionSheet = nil;
    }
    NSString* permaLink = self.post.permaLink;
    	
    if (NSClassFromString(@"UIActivity") != nil) {
        NSString *title = self.post.postTitle;
        SafariActivity *safariActivity = [[SafariActivity alloc] init];
        InstapaperActivity *instapaperActivity = [[InstapaperActivity alloc] init];
        PocketActivity *pocketActivity = [[PocketActivity alloc] init];
		
        NSMutableArray *activityItems = [NSMutableArray array];
        if (title) {
            [activityItems addObject:title];
        }
		
        [activityItems addObject:[NSURL URLWithString:permaLink]];
        UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:activityItems applicationActivities:@[safariActivity, instapaperActivity, pocketActivity]];
        [self presentViewController:activityViewController animated:YES completion:nil];
        return;
    }
	
    self.linkOptionsActionSheet = [[UIActionSheet alloc] initWithTitle:permaLink delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel", @"Cancel") destructiveButtonTitle:nil otherButtonTitles:NSLocalizedString(@"Open in Safari", @"Open in Safari"), NSLocalizedString(@"Mail Link", @"Mail Link"),  NSLocalizedString(@"Copy Link", @"Copy Link"), nil];
    self.linkOptionsActionSheet.actionSheetStyle = UIActionSheetStyleDefault;
    if(IS_IPAD ){
        [self.linkOptionsActionSheet showFromBarButtonItem:_shareButton animated:YES];
    } else {
        [self.linkOptionsActionSheet showInView:self.view];
    }
	
}


- (void)handleCloseKeyboard:(id)sender {
	if (_readerCommentFormView.window != nil) {
		[self hideCommentForm];
	} else {
		[self hideReblogForm];
	}
    BOOL hideBars = !self.navigationController.toolbarHidden;
    if (!hideBars || self.tableView.contentOffset.y > 60) {
        [self.navigationController setToolbarHidden:hideBars animated:YES];
        [self setFullScreen:hideBars];
    }
}

- (BOOL)isReplying {
	return ([self.tableView indexPathForSelectedRow] != nil) ? YES : NO;
}


- (void)showStoredComment {
	NSDictionary *storedComment = [self.post getStoredComment];
	if (!storedComment) {
		return;
	}
	
	[_readerCommentFormView setText:[storedComment objectForKey:@"comment"]];
	
	NSNumber *commentID = [storedComment objectForKey:@"commentID"];
	NSInteger cid = [commentID integerValue];
	
	if (cid == 0) return;

	NSUInteger idx = [_comments indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
		ReaderComment *c = (ReaderComment *)obj;
		if([c.commentID integerValue] == cid) {
			return YES;
		}
		return NO;
	}];
	NSIndexPath *path = [NSIndexPath indexPathForRow:idx inSection:0];
	[self.tableView selectRowAtIndexPath:path animated:NO scrollPosition:UITableViewScrollPositionNone];
	_readerCommentFormView.comment = [_comments objectAtIndex:idx];
}


- (void)showCommentForm {
	[self hideReblogForm];
	
	if (_readerCommentFormView.superview != nil) {
		return;
	}
	
	NSIndexPath *path = [self.tableView indexPathForSelectedRow];
	if (path) {
		_readerCommentFormView.comment = (ReaderComment *)[self.resultsController objectAtIndexPath:path];
	}
	
	CGFloat formHeight = [ReaderCommentFormView desiredHeight];
	CGRect tableFrame = self.tableView.frame;
	tableFrame.size.height = self.tableView.frame.size.height - formHeight;
	self.tableView.frame = tableFrame;
	
	CGFloat y = tableFrame.origin.y + tableFrame.size.height;
	_readerCommentFormView.frame = CGRectMake(0.0f, y, self.view.bounds.size.width, formHeight);
	[self.view addSubview:_readerCommentFormView];
	self.isShowingCommentForm = YES;
	[_readerCommentFormView.textView becomeFirstResponder];
}


- (void)hideCommentForm {
	if(_readerCommentFormView.superview == nil) {
		return;
	}
	
	_readerCommentFormView.comment = nil;
	[self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:NO];
	
	CGRect tableFrame = self.tableView.frame;
	tableFrame.size.height = self.tableView.frame.size.height + _readerCommentFormView.frame.size.height;
	
	self.tableView.frame = tableFrame;
	[_readerCommentFormView removeFromSuperview];
	self.isShowingCommentForm = NO;
	[self.view endEditing:YES];
}


- (void)showReblogForm {
	[self hideCommentForm];
	
	if (_readerReblogFormView.superview != nil) {
		return;
	}
	
	CGFloat reblogHeight = [ReaderReblogFormView desiredHeight];
	CGRect tableFrame = self.tableView.frame;
	tableFrame.size.height = self.tableView.frame.size.height - reblogHeight;
	self.tableView.frame = tableFrame;
	
	CGFloat y = tableFrame.origin.y + tableFrame.size.height;
	_readerReblogFormView.frame = CGRectMake(0.0f, y, self.view.bounds.size.width, reblogHeight);
	[self.view addSubview:_readerReblogFormView];
	self.isShowingReblogForm = YES;
	[_readerReblogFormView.textView becomeFirstResponder];
}


- (void)hideReblogForm {
	if(_readerReblogFormView.superview == nil) {
		return;
	}
	
	[self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:NO];
	
	CGRect tableFrame = self.tableView.frame;
	tableFrame.size.height = self.tableView.frame.size.height + _readerReblogFormView.frame.size.height;
	
	self.tableView.frame = tableFrame;
	[_readerReblogFormView removeFromSuperview];
	self.isShowingReblogForm = NO;
	[self.view endEditing:YES];
}

- (void)setFullScreen:(BOOL)fullScreen {
    [self.navigationController setToolbarHidden:fullScreen animated:YES];
    [self.navigationController setNavigationBarHidden:fullScreen animated:YES];
    return;

    if (fullScreen) {
        [UIView animateWithDuration:.3f
                         animations:^{
                             self.navigationController.toolbar.alpha = 0.f;
                             self.navigationController.navigationBar.alpha = 0.f;
                         } completion:^(BOOL finished) {
                             [self.navigationController setToolbarHidden:YES animated:NO];
                             [self.navigationController setNavigationBarHidden:YES animated:NO];
                         }];
    } else {
        [self.navigationController setToolbarHidden:NO animated:NO];
        self.navigationController.toolbar.alpha = 0.f;
        [self.navigationController setNavigationBarHidden:NO animated:NO];
        self.navigationController.navigationBar.alpha = 0.f;
        [UIView animateWithDuration:.3f
                         animations:^{
                             self.navigationController.toolbar.alpha = 1.f;
                             self.navigationController.navigationBar.alpha = 1.f;
                         }];
    }
}

#pragma mark - Sync methods

- (NSDate *)lastSyncDate {
	return self.post.dateCommentsSynced;
}


- (void)syncWithUserInteraction:(BOOL)userInteraction {
	
	if ([self.post.postID integerValue] == 0 ) { // Weird that this should ever happen. 
		self.post.dateCommentsSynced = [NSDate date];
		[self performSelector:@selector(hideRefreshHeader) withObject:self afterDelay:0.5f];
		return;
	}
	
	NSDictionary *params = @{@"number":[NSNumber numberWithInteger:ReaderCommentsToSync]};

	[ReaderPost getCommentsForPost:[self.post.postID integerValue]
						  fromSite:[self.post.siteID stringValue]
					withParameters:params
						   success:^(AFHTTPRequestOperation *operation, id responseObject) {
							   [self onSyncSuccess:operation response:responseObject];
						   } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
							   [self onSyncFailure:operation error:error];
						   }];
}


- (void)loadMoreWithSuccess:(void (^)())success failure:(void (^)(NSError *error))failure {
	if ([self.resultsController.fetchedObjects count] == 0) {
		return;
	}
	
	if (_loadingMore) return;
	_loadingMore = YES;
	
	NSUInteger numberToSync = [_comments count] + ReaderCommentsToSync;
	NSDictionary *params = @{@"number":[NSNumber numberWithInteger:numberToSync]};

	[ReaderPost getCommentsForPost:[self.post.postID integerValue]
						  fromSite:[self.post.siteID stringValue]
					withParameters:params
						   success:^(AFHTTPRequestOperation *operation, id responseObject) {
							   [self onSyncSuccess:operation response:responseObject];
						   } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
							   [self onSyncFailure:operation error:error];
						   }];
}


- (BOOL)hasMoreContent {
	return _hasMoreContent;
}


- (void)onSyncSuccess:(AFHTTPRequestOperation *)operation response:(id)responseObject {
	self.post.dateCommentsSynced = [NSDate date];
	
	NSDictionary *resp = (NSDictionary *)responseObject;
	NSArray *commentsArr = [resp arrayForKey:@"comments"];
	
	if (!commentsArr) {
		_hasMoreContent = NO;
		return;
	}
	
	if([commentsArr count] < ([_comments count] + ReaderCommentsToSync)) {
		_hasMoreContent = NO;
	}
	
	[ReaderComment syncAndThreadComments:commentsArr
								 forPost:self.post
							 withContext:[[WordPressAppDelegate sharedWordPressApplicationDelegate] managedObjectContext]];
	
	[self prepareComments];
	[self.tableView reloadData];

	if ([self.resultsController.fetchedObjects count] > 0) {
		self.tableView.backgroundColor = [UIColor colorWithHexString:@"EFEFEF"];
	}

}


- (void)onSyncFailure:(AFHTTPRequestOperation *)operation error:(NSError *)error {
	// TODO: prompt about failure.
}


#pragma mark - UITableView Delegate Methods

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (![_comments count]) {
		return 0.0f;
	}
	
	ReaderComment *comment = [_comments objectAtIndex:indexPath.row];
	return [ReaderCommentTableViewCell heightForComment:comment
												  width:tableView.frame.size.width
											 tableStyle:tableView.style
										  accessoryType:UITableViewCellAccessoryNone];
}


- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return [_comments count];
}


- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSString *cellIdentifier = @"ReaderCommentCell";
    ReaderCommentTableViewCell *cell = (ReaderCommentTableViewCell *)[self.tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (cell == nil) {
        cell = [[ReaderCommentTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
		cell.parentController = self;
    }
	cell.accessoryType = UITableViewCellAccessoryNone;
		
	ReaderComment *comment = [_comments objectAtIndex:indexPath.row];
	[cell configureCell:comment];

	return cell;	
}


- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	
	if (_readerReblogFormView.window != nil) {
		[self hideReblogForm];
		return nil;
	}
	
	if (_readerCommentFormView.window != nil) {
		UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
		if ([cell isSelected]) {
			[tableView deselectRowAtIndexPath:indexPath animated:NO];
		}
		
		[self hideCommentForm];
		return nil;
	}
	
	[self showCommentForm];

	return indexPath;
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	_readerCommentFormView.comment = [_comments objectAtIndex:indexPath.row];
	if (IS_IPAD) {
		[self.tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionBottom animated:YES];
	} else {
		[self.tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionTop animated:YES];
	}
}


- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleNone;
}


- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}


#pragma mark - UIScrollView Delegate Methods

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
	if (_isScrollingCommentIntoView){
		self.isScrollingCommentIntoView = NO;
	}
    CGFloat dY = scrollView.contentOffset.y - _previousOffset;
    BOOL toolbarHidden = self.navigationController.toolbarHidden;
    if (toolbarHidden &&
        (dY < 0
         || (dY > 0 && scrollView.contentOffset.y < 10)
         || (dY > 0 && scrollView.contentOffset.y > _headerView.frame.size.height))) {
            [self setFullScreen:NO];
    }

    // Should be around the start of the post
    CGFloat hideThreshold = 60;
    if (!toolbarHidden && _previousOffset < hideThreshold && scrollView.contentOffset.y > hideThreshold) {
        [self setFullScreen:YES];
    }

    _previousOffset = scrollView.contentOffset.y;
}


- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
	
	if (_readerReblogFormView.window) {
		[self hideReblogForm];
		return;
	}
	
	NSIndexPath *selectedIndexPath = [self.tableView indexPathForSelectedRow];
	if (!selectedIndexPath) {
		[self hideCommentForm];
	}
	
	__block BOOL found = NO;
	[[self.tableView indexPathsForVisibleRows] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
		NSIndexPath *objPath = (NSIndexPath *)obj;
		if ([objPath compare:selectedIndexPath] == NSOrderedSame) {
			found = YES;
		}
		*stop = YES;
	}];
	
	if (found) return;
	
	[self hideCommentForm];

}


#pragma mark - ReaderPostDetailView Delegate Methods

- (void)readerPostDetailViewLayoutChanged {
	self.tableView.tableHeaderView = _headerView;
}


#pragma mark - ReaderTextForm Delegate Methods

- (void)readerTextFormDidCancel:(ReaderTextFormView *)readerTextForm {
	if ([readerTextForm isEqual:_readerCommentFormView]) {
		[self hideCommentForm];
	} else {
		[self hideReblogForm];
	}
}


- (void)readerTextFormDidSend:(ReaderTextFormView *)readerTextForm {
	if ([readerTextForm isEqual:_readerCommentFormView]) {
		[self hideCommentForm];
		self.post.storedComment = nil;
		[self prepareComments];
		[self.tableView reloadData];
	} else {
		[self hideReblogForm];
	}
}


- (void)readerTextFormDidChange:(ReaderTextFormView *)readerTextForm {
	// If we are replying, and scrolled away from the comment, scroll back to it real quick.
	if ([readerTextForm isEqual:_readerCommentFormView] && [self isReplying] && !_isScrollingCommentIntoView) {
		NSIndexPath *path = [self.tableView indexPathForSelectedRow];
		if (NSOrderedSame != [path compare:[self.tableView.indexPathsForVisibleRows objectAtIndex:0]]) {
			self.isScrollingCommentIntoView = YES;
			[self.tableView scrollToRowAtIndexPath:path atScrollPosition:UITableViewScrollPositionTop animated:YES];
		}
	}
}


- (void)readerTextFormDidEndEditing:(ReaderTextFormView *)readerTextForm {
	if (![readerTextForm isEqual:_readerCommentFormView]) {
		return;
	}
	
	if ([readerTextForm.text length] > 0) {
		// Save the text
		NSNumber *commentID = nil;
		if ([self isReplying]){
			ReaderComment *comment = [_comments objectAtIndex:[self.tableView indexPathForSelectedRow].row];
			commentID = comment.commentID;
		}
		[self.post storeComment:commentID comment:[readerTextForm text]];
	} else {
		self.post.storedComment = nil;
	}
	[self.post save];

}


#pragma mark - DetailView Delegate Methods

- (void)resetView {
	
}


#pragma mark -
#pragma mark Fetched results controller

- (NSFetchedResultsController *)resultsController {
    if (_resultsController != nil) {
        return _resultsController;
    }
	
	NSString *entityName = @"ReaderComment";
	NSManagedObjectContext *moc = [[WordPressAppDelegate sharedWordPressApplicationDelegate] managedObjectContext];
	
	NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    [fetchRequest setEntity:[NSEntityDescription entityForName:@"ReaderComment" inManagedObjectContext:moc]];
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"(post = %@) && (parentID = 0)", self.post];
    [fetchRequest setPredicate:predicate];
    NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"dateCreated" ascending:YES];
    [fetchRequest setSortDescriptors:[NSArray arrayWithObject:sortDescriptor]];
    
	_resultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest
                                                             managedObjectContext:moc
                                                               sectionNameKeyPath:nil
                                                                        cacheName:nil];
	
    NSError *error = nil;
    if (![_resultsController performFetch:&error]) {
        WPFLog(@"%@ couldn't fetch %@: %@", self, entityName, [error localizedDescription]);
        _resultsController = nil;
    }
    
    return _resultsController;
}


#pragma mark - UIActionSheet Delegate Methods

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex {
	
	NSString *permaLink = self.post.permaLink;
	
	if (buttonIndex == 0) {
		NSURL *permaLinkURL;
		permaLinkURL = [[NSURL alloc] initWithString:(NSString *)permaLink];
        [[UIApplication sharedApplication] openURL:(NSURL *)permaLinkURL];
		
    } else if (buttonIndex == 1) {
        MFMailComposeViewController* controller = [[MFMailComposeViewController alloc] init];
        controller.mailComposeDelegate = self;
        
        NSString *title = self.post.postTitle;
        [controller setSubject: [title trim]];
        
        NSString *body = [permaLink trim];
        [controller setMessageBody:body isHTML:NO];
        
        if (controller)
            [self.panelNavigationController presentModalViewController:controller animated:YES];
		
        [self setMFMailFieldAsFirstResponder:controller.view mfMailField:@"MFRecipientTextField"];
		
    } else if ( buttonIndex == 2 ) {
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        pasteboard.string = permaLink;
    }
}


#pragma mark - MFMailComposeViewControllerDelegate

- (void)mailComposeController:(MFMailComposeViewController*)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError*)error {
	[self dismissModalViewControllerAnimated:YES];
}

//Returns true if the ToAddress field was found any of the sub views and made first responder
//passing in @"MFComposeSubjectView"     as the value for field makes the subject become first responder
//passing in @"MFComposeTextContentView" as the value for field makes the body become first responder
//passing in @"RecipientTextField"       as the value for field makes the to address field become first responder
- (BOOL)setMFMailFieldAsFirstResponder:(UIView*)view mfMailField:(NSString*)field {
    for (UIView *subview in view.subviews) {
        
        NSString *className = [NSString stringWithFormat:@"%@", [subview class]];
        if ([className isEqualToString:field]) {
            //Found the sub view we need to set as first responder
            [subview becomeFirstResponder];
            return YES;
        }
        
        if ([subview.subviews count] > 0) {
            if ([self setMFMailFieldAsFirstResponder:subview mfMailField:field]){
                //Field was found and made first responder in a subview
                return YES;
            }
        }
    }
    
    //field not found in this view.
    return NO;
}


@end