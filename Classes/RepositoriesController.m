#import "RepositoriesController.h"
#import "RepositoryController.h"
#import "GHRepository.h"
#import "GHRepositories.h"
#import "GHOrganizations.h"
#import "GHOrganization.h"
#import "ASIHTTPRequest.h"
#import "ASIFormDataRequest.h"
#import "RepositoryCell.h"
#import "iOctocat.h"
#import "NSURL+Extensions.h"


@interface RepositoriesController ()
- (void)loadOrganizationRepositories;
- (void)displayRepositories:(GHRepositories *)repositories;
- (NSMutableArray *)repositoriesInSection:(NSInteger)section;
@end


@implementation RepositoriesController

@synthesize user;
@synthesize privateRepositories;
@synthesize publicRepositories;
@synthesize watchedRepositories;
@synthesize organizationRepositories;

- (id)initWithUser:(GHUser *)theUser {
    [super initWithNibName:@"Repositories" bundle:nil];
	self.user = theUser;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if (!user) {
        // Set to currentUser in case this controller is initialized from the TabBar
        self.user = self.currentUser;
        NSURL *repositoriesURL = [NSURL URLWithString:kUserAuthenticatedReposFormat];
        self.user.repositories = [GHRepositories repositoriesWithURL:repositoriesURL];
    }
	self.organizationRepositories = [NSMutableArray array];
	orgReposLoaded = 0;
	
	[user.organizations addObserver:self forKeyPath:kResourceLoadingStatusKeyPath options:NSKeyValueObservingOptionNew context:nil];
	[user.repositories addObserver:self forKeyPath:kResourceLoadingStatusKeyPath options:NSKeyValueObservingOptionNew context:nil];
	[user.watchedRepositories addObserver:self forKeyPath:kResourceLoadingStatusKeyPath options:NSKeyValueObservingOptionNew context:nil];   
	(user.organizations.isLoaded) ? [self loadOrganizationRepositories] : [user.organizations loadData];
	(user.repositories.isLoaded) ? [self displayRepositories:user.repositories] : [user.repositories loadData];
	(user.watchedRepositories.isLoaded) ? [self displayRepositories:user.watchedRepositories] : [user.watchedRepositories loadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [self.tableView reloadData];
}

- (void)dealloc {
	for (GHOrganization *org in user.organizations.organizations) {
		[org.repositories removeObserver:self forKeyPath:kResourceLoadingStatusKeyPath];
	}
	[user.organizations removeObserver:self forKeyPath:kResourceLoadingStatusKeyPath];
	[user.repositories removeObserver:self forKeyPath:kResourceLoadingStatusKeyPath];
	[user.watchedRepositories removeObserver:self forKeyPath:kResourceLoadingStatusKeyPath];
    [organizationRepositories release], organizationRepositories = nil;
	[noPublicReposCell release], noPublicReposCell = nil;
	[noPrivateReposCell release], noPrivateReposCell = nil;
	[noWatchedReposCell release], noWatchedReposCell = nil;
	[noOrganizationReposCell release], noOrganizationReposCell = nil;
	[publicRepositories release], publicRepositories = nil;
	[privateRepositories release], privateRepositories = nil;
    [watchedRepositories release], watchedRepositories = nil;
    [organizationRepositories release], organizationRepositories = nil;
    [super dealloc];
}

- (void)loadOrganizationRepositories {
	// GitHub API v3 changed the way this has to be looked up. There
	// is not a single call for these no more - we have to fetch each
	// organizations repos
	for (GHOrganization *org in user.organizations.organizations) {
		GHRepositories *repos = org.repositories;
		[repos addObserver:self forKeyPath:kResourceLoadingStatusKeyPath options:NSKeyValueObservingOptionNew context:nil];
		repos.isLoaded ? [self displayRepositories:repos] : [repos loadData];
	}
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if ([object isEqual:user.organizations]) {
		GHOrganizations *organizations = (GHOrganizations *)object;
		if (organizations.isLoaded) {
			[self loadOrganizationRepositories];
		} else if (organizations.error) {
			[[iOctocat sharedInstance] alert:@"Loading error" with:@"Could not load the organizations"];
		}
	} else {
		if ([keyPath isEqualToString:kResourceLoadingStatusKeyPath]) {
			GHRepositories *repositories = object;
			if (repositories.isLoaded) {
				[self displayRepositories:repositories];
			} else if (repositories.error) {
				[[iOctocat sharedInstance] alert:@"Loading error" with:@"Could not load the repositories"];
			}
		}
	}
}

- (void)displayRepositories:(GHRepositories *)repositories {
	NSComparisonResult (^compareRepositories)(GHRepository *, GHRepository *);
	compareRepositories = ^(GHRepository *repo1, GHRepository *repo2) {
		if ((id) repo1.pushedAtDate == [NSNull null]) {
			return NSOrderedDescending;
		}
		if ((id) repo2.pushedAtDate == [NSNull null]) {
			return NSOrderedAscending;
		}
		return [repo2.pushedAtDate compare:repo1.pushedAtDate];
	};
	
	// Private/Public repos
	if ([repositories isEqual:user.repositories]) {
		self.privateRepositories = [NSMutableArray array];
		self.publicRepositories = [NSMutableArray array];
		for (GHRepository *repo in user.repositories.repositories) {
			(repo.isPrivate) ? [privateRepositories addObject:repo] : [publicRepositories addObject:repo];
		}
		[self.publicRepositories sortUsingComparator:compareRepositories];
		[self.privateRepositories sortUsingComparator:compareRepositories];
    }
	// Watched repos
    else if ([repositories isEqual:user.watchedRepositories]) {
        self.watchedRepositories = [NSMutableArray arrayWithArray:user.watchedRepositories.repositories];
		[self.watchedRepositories sortUsingComparator:compareRepositories];
    }
	// Organization repos
	else {
		orgReposLoaded += 1;
		[self.organizationRepositories addObjectsFromArray:repositories.repositories];
		[self.organizationRepositories sortUsingComparator:compareRepositories];
	}
	
	// Remove already mentioned projects from watchlist
    [self.watchedRepositories removeObjectsInArray:publicRepositories];
    [self.watchedRepositories removeObjectsInArray:privateRepositories];
    [self.watchedRepositories removeObjectsInArray:organizationRepositories];
    
	[self.tableView reloadData];
}

- (GHUser *)currentUser {
	return [[iOctocat sharedInstance] currentUser];
}

- (NSMutableArray *)repositoriesInSection:(NSInteger)section {
	switch (section) {
		case 0: return privateRepositories;
		case 1: return publicRepositories;
        case 2: return organizationRepositories;
		default: return watchedRepositories;
	}
}

#pragma mark TableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return user.repositories.isLoaded ? 4 : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (!user.repositories.isLoaded) return 1;
	NSInteger count = [[self repositoriesInSection:section] count];
	return count == 0 ? 1 : count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (!user.repositories.isLoaded) return @"";
	if (section == 0) return @"Private";
	if (section == 1) return @"Public";
    if (section == 2) return @"Organizations";
	return @"Watched";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (!user.repositories.isLoaded) return loadingReposCell;
	if (indexPath.section == 0 && self.privateRepositories.count == 0) return noPrivateReposCell;
	if (indexPath.section == 1 && self.publicRepositories.count == 0) return noPublicReposCell;
	if (indexPath.section == 2 && orgReposLoaded == 0) return loadingReposCell;
	if (indexPath.section == 2 && self.organizationRepositories.count == 0) return noOrganizationReposCell;
	if (indexPath.section == 3 && !user.watchedRepositories.isLoaded) return loadingReposCell;
	if (indexPath.section == 3 && self.watchedRepositories.count == 0) return noWatchedReposCell;
	RepositoryCell *cell = (RepositoryCell *)[tableView dequeueReusableCellWithIdentifier:kRepositoryCellIdentifier];
	if (cell == nil) cell = [[[RepositoryCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kRepositoryCellIdentifier] autorelease];
	NSArray *repos = [self repositoriesInSection:indexPath.section];
	cell.repository = [repos objectAtIndex:indexPath.row];
	if (indexPath.section == 0 || indexPath.section == 1) [cell hideOwner];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	NSArray *repos = [self repositoriesInSection:indexPath.section];
	if (repos.count == 0) return;
	GHRepository *repo = [repos objectAtIndex:indexPath.row];
	RepositoryController *repoController = [[RepositoryController alloc] initWithRepository:repo];
	repoController.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:repoController animated:YES];
	[repoController release];
}

#pragma mark Autorotation

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation {
	return YES;
}

@end

