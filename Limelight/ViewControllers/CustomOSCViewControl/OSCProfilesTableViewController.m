//
//  OSCProfilesTableViewController.m
//  Moonlight
//
//  Created by Long Le on 11/28/22.
//  Copyright © 2022 Moonlight Game Streaming Project. All rights reserved.
//

#import "OSCProfilesTableViewController.h"
#import "LayoutOnScreenControlsViewController.h"
#import "ProfileTableViewCell.h"
#import "OSCProfile.h"
#import "OnScreenButtonState.h"
#import "OSCProfilesManager.h"
#import "LocalizationHelper.h"

const double NAV_BAR_HEIGHT = 50;

@interface OSCProfilesTableViewController ()

@end

@implementation OSCProfilesTableViewController {
    OSCProfilesManager *profilesManager;
    LayoutOnScreenControlsViewController *parentLayoutOSCViewController;
}

@synthesize tableView;

- (void) viewWillDisappear:(BOOL)animated{
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"OscLayoutTableViewCloseNotification" object:self]; // notify other view that oscLayoutManager is closing
}


- (void) viewDidLoad {
    [super viewDidLoad];
    
    
    profilesManager = [OSCProfilesManager sharedManager];
    
    self.tableView.tableHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, NAV_BAR_HEIGHT)];
    
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    
    [self.tableView registerNib:[UINib nibWithNibName:@"ProfileTableViewCell" bundle:nil]
         forCellReuseIdentifier:@"Cell"]; // Register the custom cell nib file with the table view
    self.tableView.alpha = 0.5;
    self.tableView.backgroundColor = [[UIColor colorWithRed:0.5 green:0.7 blue:1.0 alpha:1.0] colorWithAlphaComponent:0.5]; // set background color & transparency
}

- (void) viewDidAppear:(BOOL)animated {
    [super viewDidAppear: animated];
    
    self.tableView.tableHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, NAV_BAR_HEIGHT)];

    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    
    [self.tableView registerNib:[UINib nibWithNibName:@"ProfileTableViewCell" bundle:nil]
                                        forCellReuseIdentifier:@"Cell"]; // Register the custom cell nib file with the table view

    if ([[profilesManager getAllProfiles] count] > 0) { // scroll to selected profile if user has any saved profiles
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:[profilesManager getIndexOfSelectedProfile] inSection:0];
        [self.tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
     }
}


#pragma mark - UIButton Actions

/* Loads the OSC profile that user selected, dismisses this VC, then tells the presenting view controller to lay out the on screen buttons according to the selected profile's instructions */
- (IBAction) duplicateTapped:(id)sender {

        UIAlertController * inputNameAlertController = [UIAlertController alertControllerWithTitle: [LocalizationHelper localizedStringForKey:@"Enter the name you want to save this controller profile as"] message: @"" preferredStyle:UIAlertControllerStyleAlert];
        [inputNameAlertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {  // pop up notification with text field where user can enter the text they wish to name their OSC layout profile
            textField.placeholder = [LocalizationHelper localizedStringForKey:@"name"];
            textField.textColor = [UIColor lightGrayColor];
            textField.clearButtonMode = UITextFieldViewModeWhileEditing;
            textField.borderStyle = UITextBorderStyleNone;
        }];
        [inputNameAlertController addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"Save"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {   // add save button to allow user to save the on screen controller configuration
            NSArray *textFields = inputNameAlertController.textFields;
            UITextField *nameField = textFields[0];
            NSString *enteredProfileName = nameField.text;
            
            if ([enteredProfileName isEqualToString:@"Default"]) {  // don't let user user overwrite the 'Default' profile
                UIAlertController *alertController = [UIAlertController alertControllerWithTitle: [NSString stringWithFormat:@""] message: [LocalizationHelper localizedStringForKey:@"Saving over the 'Default' profile is not allowed"] preferredStyle:UIAlertControllerStyleAlert];
                
                [alertController addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"Ok"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                    [alertController dismissViewControllerAnimated:NO completion:^{
                        [self presentViewController:inputNameAlertController animated:YES completion:nil];
                    }];
                }]];
                [self presentViewController:alertController animated:YES completion:nil];
            }
            else if ([enteredProfileName length] == 0) {    // if user entered no text and taps the 'Save' button let them know they can't do that
                UIAlertController * savedAlertController = [UIAlertController alertControllerWithTitle: [NSString stringWithFormat:@""] message: [LocalizationHelper localizedStringForKey:@"Profile name cannot be blank!"] preferredStyle:UIAlertControllerStyleAlert];
                
                [savedAlertController addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"Ok"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { // show pop up notification letting user know they must enter a name in the text field if they wish to save the controller profile
                    
                    [savedAlertController dismissViewControllerAnimated:NO completion:^{
                        [self presentViewController:inputNameAlertController animated:YES completion:nil];
                    }];
                }]];
                [self presentViewController:savedAlertController animated:YES completion:nil];
            }
            else if ([self->profilesManager profileNameAlreadyExist:enteredProfileName] == YES) {  // if the entered profile name already
                UIAlertController * savedAlertController = [UIAlertController alertControllerWithTitle: [NSString stringWithFormat:@""] message: [LocalizationHelper localizedStringForKey:@"Profile name already exists"] preferredStyle:UIAlertControllerStyleAlert];
                
                [savedAlertController addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"Ok"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                    //[savedAlertController dismissViewControllerAnimated:NO completion:nil];
                    //[self profileViewRefresh]; //refresh profile view after saving new profile;
                }]];
                [self presentViewController:savedAlertController animated:YES completion:nil];
            }
            else {  // if user entered a valid name that doesn't already exist then save the profile to persistent storage
                [self->profilesManager saveProfileWithName: enteredProfileName andButtonLayers:self.currentOSCButtonLayers]; // the OSC layout here is passed from parent LayoutOSCViewController;
                [self->profilesManager setProfileToSelected: enteredProfileName];
                
                UIAlertController * savedAlertController = [UIAlertController alertControllerWithTitle: [NSString stringWithFormat:@""] message: [LocalizationHelper localizedStringForKey:@"Profile %@ duplicated from current layout", enteredProfileName] preferredStyle:UIAlertControllerStyleAlert];  // Let user know this profile has been duplicated & saved
                
                [savedAlertController addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"Ok"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                    [savedAlertController dismissViewControllerAnimated:NO completion:nil];
                    [self profileViewRefresh]; //refresh profile view after saving new profile;
                }]];
                [self presentViewController:savedAlertController animated:YES completion:nil];
            }
        }]];
        [inputNameAlertController addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"Cancel"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { // adds a button that allows user to decline the option to save the controller layout they currently see on screen
            [inputNameAlertController dismissViewControllerAnimated:NO completion:nil];
        }]];
        [self presentViewController:inputNameAlertController animated:YES completion:nil];
}

/* basically the same with loadTapped */
- (void) profileViewRefresh{
    //[self dismissViewControllerAnimated:YES completion:nil];
    //[selfparentLayoutOSCViewController]
    [self.tableView reloadData]; // table view will be refreshed by calling reloadData
    if (self.didDismissOSCProfilesTVC) {    // tells the presenting view controller to lay out the on screen buttons according to the selected profile's instructions
        self.didDismissOSCProfilesTVC();
    }
}

- (IBAction) deleteTapped:(id)sender{// delete can be executed simply by calling this 2 methods.
    [profilesManager deleteCurrentSelectedProfile];
    [self profileViewRefresh];
}


- (IBAction) exitTapped:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}


#pragma mark - TableView DataSource

- (NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [[profilesManager getAllProfiles] count];
}

- (UITableViewCell *) tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ProfileTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
    OSCProfile *profile = [[profilesManager getAllProfiles] objectAtIndex: indexPath.row];
    cell.name.text = profile.name;
    cell.backgroundColor = [[UIColor clearColor] colorWithAlphaComponent:0.99];
    
    if ([profile.name isEqualToString: [profilesManager getSelectedProfile].name]) { // if this cell contains the name of the currently selected OSC profile then add a checkmark to the right side of the cell
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    }
    else {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    return cell;
}

- (BOOL) tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void) tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    NSMutableArray *profiles = [profilesManager getAllProfiles];

    if ([[[profiles objectAtIndex:indexPath.row] name] isEqualToString:@"Default"]) {   // if user is attempting to delete the 'Default' profile then show a pop up telling user they can't do that and return out of this method
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle: [NSString stringWithFormat:@""] message: @"Deleting the 'Default' profile is not allowed" preferredStyle:UIAlertControllerStyleAlert];
        
        [alertController addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"Ok"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [alertController dismissViewControllerAnimated:NO completion:nil];
        }]];
        [self presentViewController:alertController animated:YES completion:nil];
        
        return;
    }
    
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        OSCProfile *profile = [profiles objectAtIndex:indexPath.row];
        if (profile.isSelected) {   // if user is deleting the currently selected OSC profile then make the  profile at its previous index the currently selected profile
            if (indexPath.row > 0) {    // check that row is greater than zero to avoid an out of bounds crash, although that should not be possible right now since the 'Default' profile is always at row 0 and they're not allowed to delete it
                OSCProfile *profile = [profiles objectAtIndex:indexPath.row - 1];
                profile.isSelected = YES;
            }
        }
        
        [profiles removeObjectAtIndex:indexPath.row];
        
        /* save OSC profiles array to persistent storage */
        NSMutableArray *profilesEncoded = [[NSMutableArray alloc] init];
        for (OSCProfile *profileDecoded in profiles) {  // encode each OSC profile object and add them to an array
            
            NSData *profileEncoded = [NSKeyedArchiver archivedDataWithRootObject:profileDecoded requiringSecureCoding:YES error:nil];
            [profilesEncoded addObject:profileEncoded];
        }
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:profilesEncoded
                                             requiringSecureCoding:YES error:nil];  // encode the array itself, NOT the objects in the array
        [[NSUserDefaults standardUserDefaults] setObject:data forKey:@"OSCProfiles"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        
        [tableView reloadData]; 
    }
}


#pragma mark - TableView Delegate

/* When user taps a cell it moves the checkmark to that cell indicating to the user the profile associated with that cell is now the selected profile. It also sets that cell's associated OSCProfile object's 'isSelected' property to YES  */
- (void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSIndexPath *selectedIndexPath = [NSIndexPath indexPathForRow:indexPath.row inSection:0];
    NSIndexPath *lastSelectedIndexPath = [NSIndexPath indexPathForRow:[profilesManager getIndexOfSelectedProfile] inSection:0];

    if (selectedIndexPath != lastSelectedIndexPath) {
        /* Place checkmark on selected cell and set profile associated with cell as selected profile */
        UITableViewCell *selectedCell = [tableView cellForRowAtIndexPath: selectedIndexPath];
        selectedCell.accessoryType = UITableViewCellAccessoryCheckmark;  // add checkmark to the cell the user tapped
        OSCProfile *profile = [[profilesManager getAllProfiles] objectAtIndex:indexPath.row];
        [profilesManager setProfileToSelected: profile.name];   // set the profile associated with this cell's 'isSelected' property to YES
        
        /* Remove checkmark on the previously selected cell  */
        UITableViewCell *lastSelectedCell = [tableView cellForRowAtIndexPath: lastSelectedIndexPath];
        lastSelectedCell.accessoryType = UITableViewCellAccessoryNone; 
        [tableView deselectRowAtIndexPath:lastSelectedIndexPath animated:YES];
    }
    [self profileViewRefresh]; // update OSC layout when table view option is changed
}


@end
