//
//  SimpleFileListTableViewController.m
//  Owncloud iOs Client
//
//  Created by Javier Gonzalez on 04/11/14.
//
//

#import "SimpleFileListTableViewController.h"
#import "ManageUsersDB.h"
#import "ManageFilesDB.h"
#import "UserDto.h"
#import "FileDto.h"
#import "CustomCellFileAndDirectory.h"
#import "InfoFileUtils.h"
#import "constants.h"
#import "FileNameUtils.h"
#import "EmptyCell.h"
#import "Customization.h"
#import "DocumentPickerViewController.h"
#import "OCCommunication.h"
#import "UtilsDtos.h"
#import "OCFileDto.h"
#import "OCErrorMsg.h"
#import "UtilsUrls.h"
#import "FileListDBOperations.h"
#import "UIColor+Constants.h"

NSString *userHasChangeNotification = @"userHasChangeNotification";

@interface SimpleFileListTableViewController ()

@end

@implementation SimpleFileListTableViewController

- (id) initWithNibName:(NSString *)nibNameOrNil onFolder:(FileDto *)currentFolder {
    
    self = [super initWithNibName:nibNameOrNil bundle:nil];
    
    if (self) {
        
        self.manageNetworkErrors = [ManageNetworkErrors new];
        self.manageNetworkErrors.delegate = self;
        self.currentFolder = currentFolder;
        self.user = [ManageUsersDB getActiveUser];
        self.currentDirectoryArray = [ManageFilesDB getFilesByFileIdForActiveUser: (int)currentFolder.idFile];
        self.sortedArray = [self partitionObjects:self.currentDirectoryArray collationStringSelector:@selector(fileName)];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.user = [ManageUsersDB getActiveUser];
    
    //If it is the root folder show the icon of root folder
    if(self.currentFolder.isRootFolder) {
        
        if(k_show_logo_on_title_file_list) {
            UIImageView *imageView = [[UIImageView alloc]initWithImage:[UIImage imageNamed:[FileNameUtils getTheNameOfTheBrandImage]]];
            self.navigationItem.titleView = imageView;
        }
    } else {
        //We remove the las character / and the URL encoding
        NSString *title = [self.currentFolder.fileName stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        if ([title length] > 0) {
            title = [title substringToIndex:[title length] - 1];
        }
        
        [self.navigationItem setTitle:title];
    }
    
    [self addPullDownRefresh];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    //We need to catch the rotation notifications only in iPhone.
    if (IS_IPHONE) {
        [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(orientationChange:) name:UIApplicationWillChangeStatusBarOrientationNotification object:nil];
    }
    
    [self reloadFolderByEtag];
}

- (void)viewWillDisappear:(BOOL)animated{
    [super viewWillDisappear:animated];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


#pragma mark - Check User

- (BOOL) isTheSameUserHereAndOnTheDatabase {
    
    UserDto *userFromDB = [ManageUsersDB getActiveUser];
    
    BOOL isTheSameUser = NO;
    
    if (userFromDB.idUser == self.user.idUser) {
        self.user = userFromDB;
        isTheSameUser = YES;
    }
    
    return isTheSameUser;

}
    
- (void)orientationChange:(NSNotification*)notification
{
    UIInterfaceOrientation orientation = (UIInterfaceOrientation)[[notification.userInfo objectForKey:UIApplicationStatusBarOrientationUserInfoKey] intValue];
    
    if(UIInterfaceOrientationIsPortrait(orientation)){
        [self performSelector:@selector(refreshTheInterfaceInPortrait) withObject:nil afterDelay:0.0];
    }
}

//We have to remove the status bar height in navBar and view after rotate
- (void) refreshTheInterfaceInPortrait{
    
    CGRect frameNavigationBar = self.navigationController.navigationBar.frame;
    CGRect frameView = self.view.frame;
    frameNavigationBar.origin.y -= 20;
    frameView.origin.y -= 20;
    frameView.size.height += 20;
    
    self.navigationController.navigationBar.frame = frameNavigationBar;
    self.view.frame = frameView;

}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    //If the _currentDirectoryArray doesn't have object it will have one section
    NSInteger sections = 1;
    if ([_currentDirectoryArray count] > 0) {
        sections = [[[UILocalizedIndexedCollation currentCollation] sectionTitles] count];
    }
    return sections;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    //If the _currentDirectoryArray doesn't have object it will have one row
    NSInteger rows = 1;
    if ([_currentDirectoryArray count] > 0) {
        rows = [[_sortedArray objectAtIndex:section] count];
    }
    return rows;
}

// Returns the table view managed by the controller object.
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    //Only show the section title if there are rows in it
    BOOL showSection = [[_sortedArray objectAtIndex:section] count] != 0;
    NSArray *titles = [[UILocalizedIndexedCollation currentCollation] sectionTitles];
    
    if(k_minimun_files_to_show_separators > [_currentDirectoryArray count]) {
        showSection = NO;
    }
    return (showSection) ? [titles objectAtIndex:section] : nil;
}

// Asks the data source to return the titles for the sections for a table view.
- (NSArray *)sectionIndexTitlesForTableView:(UITableView *)tableView
{
    // The commented part is for the version with searchField
    
    if(k_minimun_files_to_show_separators > [_currentDirectoryArray count]) {
        return nil;
    } else {
        tableView.sectionIndexColor = [UIColor colorOfSectionIndexColorFileList];
        return [[UILocalizedIndexedCollation currentCollation] sectionIndexTitles];
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    UITableViewCell *cell;
    
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    
    
    if ([_currentDirectoryArray count] == 0) {
        
        self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
        
        //If the _currentDirectoryArray doesn't have object will show a message
        //Identifier
        static NSString *CellIdentifier = @"EmptyCell";
        EmptyCell *emptyFileCell = (EmptyCell *)[tableView dequeueReusableCellWithIdentifier:CellIdentifier];
        
        if (emptyFileCell == nil) {
            // Load the top-level objects from the custom cell XIB.
            NSArray *topLevelObjects = [[NSBundle mainBundle] loadNibNamed:@"EmptyCell" owner:self options:nil];
            // Grab a pointer to the first object (presumably the custom cell, as that's all the XIB should contain).
            emptyFileCell = (EmptyCell *)[topLevelObjects objectAtIndex:0];
        }
        
        //Autoresizing width when the iPhone is on landscape
        if (IS_IPHONE) {
            [emptyFileCell.textLabel setAutoresizingMask:UIViewAutoresizingFlexibleWidth];
        }
        
        NSString *message = NSLocalizedString(@"message_not_files", nil);
        emptyFileCell.textLabel.text = message;
        emptyFileCell.textLabel.textAlignment = NSTextAlignmentCenter;
        //Disable the tap
        emptyFileCell.userInteractionEnabled = NO;
        cell = emptyFileCell;
        emptyFileCell = nil;
        
    } else {
        
        static NSString *CellIdentifier = @"FileAndDirectoryCell";
        
        CustomCellFileAndDirectory *fileCell = (CustomCellFileAndDirectory *)[tableView dequeueReusableCellWithIdentifier:CellIdentifier];
        
        if (fileCell == nil) {
            NSArray *topLevelObjects = [[NSBundle mainBundle] loadNibNamed:@"CustomCellFileAndDirectory" owner:self options:nil];
            fileCell = (CustomCellFileAndDirectory *)[topLevelObjects objectAtIndex:0];
        }
        
        fileCell.indexPath = indexPath;
        
        //Autoresizing width when the iphone is landscape. Not in iPad.
        if (IS_IPHONE) {
            [fileCell.labelTitle setAutoresizingMask:UIViewAutoresizingFlexibleWidth];
            [fileCell.labelInfoFile setAutoresizingMask:UIViewAutoresizingFlexibleWidth];
        }
        
        
        FileDto *file = (FileDto *)[[_sortedArray objectAtIndex:indexPath.section]objectAtIndex:indexPath.row];
        
        NSDate* date = [NSDate dateWithTimeIntervalSince1970:file.date];
        NSString *fileDateString;
        if (file.date > 0) {
            fileDateString = [InfoFileUtils getTheDifferenceBetweenDateOfUploadAndNow:date];
        } else {
            fileDateString = @"";
        }
        
        //Add a FileDownloadedIcon.png in the left of cell when the file is in device
        if (![file isDirectory]) {
            //Is file
            //Font for file
            UIFont *fileFont = [UIFont fontWithName:@"HelveticaNeue-Light" size:17];
            fileCell.labelTitle.font = fileFont;
            fileCell.labelTitle.text = [file.fileName stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            
            NSString *fileSizeString = @"";
            //Obtain the file size from the data base
            DLog(@"Size: %ld", file.size);
            float lenghSize = file.size;
            
            //If size is <0 we do not have the size
            if (file.size >= 0) {
                if (file.size < 1024) {
                    //Bytes
                    fileSizeString = [NSString stringWithFormat:@"%.f B", lenghSize];
                } else if ((file.size/1024) < 1024){
                    //KB
                    fileSizeString = [NSString stringWithFormat:@"%.1f KB", (lenghSize/1024)];
                } else {
                    //MB
                    fileSizeString = [NSString stringWithFormat:@"%.1f MB", ((lenghSize/1024)/1024)];
                }
            }
            
            if(file.isNecessaryUpdate) {
                fileCell.labelInfoFile.text = NSLocalizedString(@"this_file_is_older", nil);
            } else {
                if ([fileDateString isEqualToString:@""]) {
                    fileCell.labelInfoFile.text = [NSString stringWithFormat:@"%@", fileSizeString];
                } else {
                    fileCell.labelInfoFile.text = [NSString stringWithFormat:@"%@, %@", fileDateString, fileSizeString];
                }
            }
        } else {
            //Is directory
            //Font for folder
            UIFont *fileFont = [UIFont fontWithName:@"HelveticaNeue" size:17];
            fileCell.labelTitle.font = fileFont;
            
            NSString *folderName = [file.fileName stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            //Quit the last character
            folderName = [folderName substringToIndex:[folderName length]-1];
            
            //Put the namefileCell.labelTitle.text
            fileCell.labelTitle.text = folderName;
            fileCell.labelInfoFile.text = [NSString stringWithFormat:@"%@", fileDateString];
        }
        
        fileCell = [InfoFileUtils getTheStatusIconOntheFile:file onTheCell:fileCell andCurrentFolder:self.currentFolder];
        
        //Custom cell for SWTableViewCell with right swipe options
        fileCell.containingTableView = tableView;
        [fileCell setCellHeight:fileCell.frame.size.height];
        
        fileCell.rightUtilityButtons = nil;
        
        //Selection style gray
        fileCell.selectionStyle=UITableViewCellSelectionStyleGray;
        
        cell = fileCell;
    }
    return cell;
}



//Return the row height
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    CGFloat height = 0.0;
    
    DLog(@"currentDirectoryArray: %d", (int) [self.currentDirectoryArray count]);
    
    //If the _currentDirectoryArray doesn't have object it will have a big row
    if ([self.currentDirectoryArray count] == 0) {
        
        height = self.tableView.bounds.size.height;
    } else {
        height = 54.0;
    }
    return height;
    
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    
    [self.tableView deselectRowAtIndexPath: indexPath animated:YES];
    
    //Check if the user is the same and does not change
    if ([self isTheSameUserHereAndOnTheDatabase]) {
        FileDto *file = (FileDto *)[[_sortedArray objectAtIndex:indexPath.section]objectAtIndex:indexPath.row];
        
        if (file.isDirectory) {
            [self checkBeforeNavigationToFolder:file];
        } else {
            //TODO: here we should return the file to the document picker or download it
        }
    } else {
        //The user has change
        
        UIAlertController *alert =   [UIAlertController
                                      alertControllerWithTitle:@""
                                      message:@"The user has change on the ownCloud App" //TODO: add a string error internationzalized
                                      preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction* ok = [UIAlertAction
                             actionWithTitle:NSLocalizedString(@"ok", nil)
                             style:UIAlertActionStyleDefault
                             handler:^(UIAlertAction * action) {
                                 [super dismissViewControllerAnimated:YES completion:^{
                                    [[NSNotificationCenter defaultCenter] postNotificationName: userHasChangeNotification object: nil];
                                 }];
                             }];
        [alert addAction:ok];
        
        [self presentViewController:alert animated:YES completion:nil];
    }
}

/*
 * Method that sorts alphabetically array by selector
 *@array -> array of sections and rows of tableview
 */
- (NSArray *)partitionObjects:(NSArray *)array collationStringSelector:(SEL)selector {
    UILocalizedIndexedCollation *collation = [UILocalizedIndexedCollation currentCollation];
    
    NSInteger sectionCount = [[collation sectionTitles] count]; //section count is take from sectionTitles and not sectionIndexTitles
    NSMutableArray *unsortedSections = [NSMutableArray arrayWithCapacity:sectionCount];
    
    //create an array to hold the data for each section
    for(int i = 0; i < sectionCount; i++) {
        [unsortedSections addObject:[NSMutableArray array]];
    }
    //put each object into a section
    for (id object in array) {
        NSInteger index = [collation sectionForObject:object collationStringSelector:selector];
        [[unsortedSections objectAtIndex:index] addObject:object];
    }
    NSMutableArray *sections = [NSMutableArray arrayWithCapacity:sectionCount];
    
    //sort each section
    for (NSMutableArray *section in unsortedSections) {
        [sections addObject:[collation sortedArrayFromArray:section collationStringSelector:selector]];
    }
    
    return sections;
}

#pragma mark - Navigation

- (void) checkBeforeNavigationToFolder:(FileDto *) file {
    
    if ([ManageFilesDB getFilesByFileIdForActiveUser: (int)file.idFile].count > 0) {
        SimpleFileListTableViewController *filesViewController = [[SimpleFileListTableViewController alloc] initWithNibName:@"SimpleFileListTableViewController" onFolder:file];
        
        [[self navigationController] pushViewController:filesViewController animated:YES];
    } else {
        [self initLoading];
        [self loadRemote:file andNavigateIfIsNecessary:YES];
    }
}

- (void) reloadCurrentFolder {
    [self loadRemote:self.currentFolder andNavigateIfIsNecessary:NO];
}

- (void) loadRemote:(FileDto *) file andNavigateIfIsNecessary:(BOOL) isNecessaryNavigate {
    
    //Set the right credentials
    if (k_is_sso_active) {
        [[DocumentPickerViewController sharedOCCommunication] setCredentialsWithCookie:self.user.password];
    } else if (k_is_oauth_active) {
        [[DocumentPickerViewController sharedOCCommunication] setCredentialsOauthWithToken:self.user.password];
    } else {
        [[DocumentPickerViewController sharedOCCommunication] setCredentialsWithUser:self.user.username andPassword:self.user.password];
    }
    
    NSString *remotePath = [UtilsDtos getRemoteUrlByFile:file andUserDto:self.user];
    remotePath = [remotePath stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    
    [[DocumentPickerViewController sharedOCCommunication] readFolder:remotePath onCommunication:[DocumentPickerViewController sharedOCCommunication] successRequest:^(NSHTTPURLResponse *response, NSArray *items, NSString *redirectedServer) {
        
        for (OCFileDto *file in items) {
            DLog(@"File: %@", file.filePath);
        }
        
        
        DLog(@"Operation response code: %d", (int)response.statusCode);
        BOOL isSamlCredentialsError=NO;
        
        //Check the login error in shibboleth
        if (k_is_sso_active && redirectedServer) {
            //Check if there are fragmens of saml in url, in this case there are a credential error
            isSamlCredentialsError = [FileNameUtils isURLWithSamlFragment:redirectedServer];
            if (isSamlCredentialsError) {
                [self errorLogin];
            }
        }
        
        if(response.statusCode != kOCErrorServerUnauthorized && !isSamlCredentialsError) {
            
            //1 - Pass the items with OCFileDto to FileDto Array
            NSMutableArray *directoryList = [UtilsDtos passToFileDtoArrayThisOCFileDtoArray:items];
            
            //2 - We update the current folder with the new etag
            FileDto *remoteFolderOfSelectedFolder;
            for (FileDto *current in directoryList) {
                if (!current.fileName) {
                    remoteFolderOfSelectedFolder = current;
                }
            }
            [ManageFilesDB updateEtagOfFileDtoByid:file.idFile andNewEtag: remoteFolderOfSelectedFolder.etag];
            
            //Send the data to DB and refresh the table
            [self deleteOldDataFromDBBeforeRefresh:directoryList ofFolder:file];
            
            if (isNecessaryNavigate) {
                
                [self endLoading];
                
                SimpleFileListTableViewController *filesViewController = [[SimpleFileListTableViewController alloc] initWithNibName:@"SimpleFileListTableViewController" onFolder:file];
                
                [[self navigationController] pushViewController:filesViewController animated:YES];
            } else {
                
                _currentDirectoryArray = [FileListDBOperations makeTheRefreshProcessWith:directoryList inThisFolder:file.idFile];
                
                //Sorted the files array
                _sortedArray = [self partitionObjects: _currentDirectoryArray collationStringSelector:@selector(fileName)];
                [self.tableView reloadData];
                
                [self stopPullRefresh];
                [self endLoading];
            }
            
            self.isRefreshInProgress = NO;
        } else {
            [self endLoading];
            [self stopPullRefresh];
        }
        
    } failureRequest:^(NSHTTPURLResponse *response, NSError *error) {
        
        DLog(@"response: %@", response);
        DLog(@"error: %@", error);
        
        [self endLoading];
        [self stopPullRefresh];
        
        [self.manageNetworkErrors manageErrorHttp:response.statusCode andErrorConnection:error andUser:self.user];
    }];
}

/*
 * This method receive the new array of the server and store the changes
 * in the Database and in the tableview
 * @param requestArray -> NSArray of path items
 */
-(void)deleteOldDataFromDBBeforeRefresh:(NSArray *) requestArray ofFolder:(FileDto *) file {
    
    //This process can not be executed twice at the same time
    if (self.isRefreshInProgress == NO) {
        self.isRefreshInProgress=YES;
        
        NSMutableArray *directoryList = [NSMutableArray arrayWithArray:requestArray];
        
        //Change the filePath from the library to our format
        for (FileDto *currentFile in directoryList) {
            //Remove part of the item file path
            NSString *partToRemove = [UtilsUrls getRemovedPartOfFilePathAnd:self.user];
            if([currentFile.filePath length] >= [partToRemove length]){
                currentFile.filePath = [currentFile.filePath substringFromIndex:[partToRemove length]];
            }
        }
        
        NSArray *listOfRemoteFilesAndFolders = [FileListDBOperations makeTheRefreshProcessWith:directoryList inThisFolder:file.idFile];
        
        [FileListDBOperations createAllFoldersByArrayOfFilesDto:listOfRemoteFilesAndFolders andLocalFolder:[UtilsUrls getLocalFolderByFilePath:file.filePath andFileName:file.fileName andUserDto:self.user]];

    }
}

#pragma mark Loading view methods

/*
 * Method that launch the loading screen and block the view
 */
-(void)initLoading {
    
    if (_HUD) {
        [_HUD removeFromSuperview];
        _HUD=nil;
    }
    
    _HUD = [[MBProgressHUD alloc]initWithView:self.view];
    _HUD.delegate = self;
    [self.view.window addSubview:_HUD];
    
    //MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.navigationController.view animated:YES];
    _HUD.labelText = NSLocalizedString(@"loading", nil);
    
    if (IS_IPHONE) {
        _HUD.dimBackground = NO;
    }else {
        _HUD.dimBackground = NO;
    }
    
    [_HUD show:YES];
    
    self.view.userInteractionEnabled = NO;
    self.navigationController.navigationBar.userInteractionEnabled = NO;
    self.tabBarController.tabBar.userInteractionEnabled = NO;
    [self.view.window setUserInteractionEnabled:NO];
}


/*
 * Method that quit the loading screen and unblock the view
 */
- (void)endLoading {
    
    // [MBProgressHUD hideAllHUDsForView:self.navigationController.view animated:YES];
    [_HUD removeFromSuperview];
    self.view.userInteractionEnabled = YES;
    self.navigationController.navigationBar.userInteractionEnabled = YES;
    self.tabBarController.tabBar.userInteractionEnabled = YES;
    [self.view.window setUserInteractionEnabled:YES];
    
}

#pragma mark - Errors

/*
 * Method called when there are a fail connection with the server
 * @NSString -> Server error msg
 */
- (void)showError:(NSString *) message {
    [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:YES];
    
    UIAlertController *alert =   [UIAlertController
                                  alertControllerWithTitle:@""
                                  message:message
                                  preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* ok = [UIAlertAction
                         actionWithTitle:NSLocalizedString(@"ok", nil)
                         style:UIAlertActionStyleDefault
                         handler:^(UIAlertAction * action)
                         {
                             
                         }];
    [alert addAction:ok];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void) errorLogin {
    if (k_is_sso_active) {
        [self showError:NSLocalizedString(@"session_expired", nil)];
    } else {
       [self showError:NSLocalizedString(@"error_login_message", nil)];
    }
}

#pragma mark - Pull Refresh

- (void) addPullDownRefresh {
    
    //Init Refresh Control
    UIRefreshControl *refresh = [UIRefreshControl new];
    //For the moment in the iOS 7 GM the attributedTitle not show properly.
    //refresh.attributedTitle =[[NSAttributedString alloc] initWithString: NSLocalizedString(@"pull_down_refresh", nil)];
    refresh.attributedTitle =nil;
    [refresh addTarget:self
                action:@selector(pullRefreshView:)
      forControlEvents:UIControlEventValueChanged];
    
    self.refreshControl = refresh;
    
    [self.tableView addSubview:self.refreshControl];
}

///-----------------------------------
/// @name Pull Refresh Table View
///-----------------------------------

/**
 * This method is called when the user do a pull refresh
 * In this method call a method where does a server request.
 * @param refresh -> UIRefreshControl object
 */

-(void)pullRefreshView:(UIRefreshControl *)refresh {
    //refresh.attributedTitle = [[NSAttributedString alloc] initWithString:NSLocalizedString(@"loading_refresh", nil)];
    refresh.attributedTitle = nil;
    
    [self performSelector:@selector(reloadCurrentFolder) withObject:nil];
}

///-----------------------------------
/// @name Stop the Pull Refresh
///-----------------------------------

/**
 * Method called when the server refresh is done in order to
 * terminate the pull refresh animation
 */
- (void)stopPullRefresh{
    
    //_refreshControl.attributedTitle = [[NSAttributedString alloc] initWithString: NSLocalizedString(@"pull_down_refresh", nil)];
    [self.refreshControl endRefreshing];
}

#pragma mark - Etag

- (void) reloadFolderByEtag {
    
    if (!self.isRefreshInProgress) {
        //Set the right credentials
        if (k_is_sso_active) {
            [[DocumentPickerViewController sharedOCCommunication] setCredentialsWithCookie:self.user.password];
        } else if (k_is_oauth_active) {
            [[DocumentPickerViewController sharedOCCommunication] setCredentialsOauthWithToken:self.user.password];
        } else {
            [[DocumentPickerViewController sharedOCCommunication] setCredentialsWithUser:self.user.username andPassword:self.user.password];
        }
        
        NSString *remotePath = [UtilsDtos getRemoteUrlByFile:self.currentFolder andUserDto:self.user];
        remotePath = [remotePath stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        
        [[DocumentPickerViewController sharedOCCommunication] readFile:remotePath onCommunication:[DocumentPickerViewController sharedOCCommunication] successRequest:^(NSHTTPURLResponse *response, NSArray *items, NSString *redirectedServer) {
            
            DLog(@"Operation response code: %d", (int)response.statusCode);
            
            BOOL isSamlCredentialsError = NO;
            
            //Check the login error in shibboleth
            if (k_is_sso_active && redirectedServer) {
                //Check if there are fragmens of saml in url, in this case there are a credential error
                isSamlCredentialsError = [FileNameUtils isURLWithSamlFragment:redirectedServer];
                if (isSamlCredentialsError) {
                    [self errorLogin];
                }
            }
            if(response.statusCode < kOCErrorServerUnauthorized && !isSamlCredentialsError) {
                //Pass the items with OCFileDto to FileDto Array
                NSMutableArray *directoryList = [UtilsDtos passToFileDtoArrayThisOCFileDtoArray:items];
                
                FileDto *remoteFile = [directoryList objectAtIndex:0];
                
                if (remoteFile.etag != self.currentFolder.etag) {
                    [self reloadCurrentFolder];
                } else {
                    DLog(@"It is the same etag");
                }
                
            }
        } failureRequest:^(NSHTTPURLResponse *response, NSError *error) {
            
            DLog(@"error: %@", error);
            DLog(@"Operation error: %d", (int) response.statusCode);
        }];
    }
}

#pragma mark - CheckAccessToServerDelegate

-(void)connectionToTheServer:(BOOL)isConnection {

}

-(void)repeatTheCheckToTheServer {
    //We check the connection here because we need to accept the certificate on the self signed server before go to the files tab
    CheckAccessToServer *mCheckAccessToServer = [[CheckAccessToServer alloc] init];
    mCheckAccessToServer.viewControllerToShow = self;
    mCheckAccessToServer.delegate = self;
    [mCheckAccessToServer isConnectionToTheServerByUrl:self.user.url];
}

-(void)badCertificateNoAcceptedByUser {
    DLog(@"Certificate refushed by user");
}

@end