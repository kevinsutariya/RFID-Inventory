//
//  TSLViewController.m
//  Inventory
//
//  Created by Brian Painter on 15/05/2013.
//  Copyright (c) 2013 Technology Solutions (UK) Ltd. All rights reserved.
//
#import <ExternalAccessory/ExternalAccessory.h>

#import "TSLAppDelegate.h"
#import "TSLSelectReaderViewController.h"
#import "TSLInventoryViewController.h"



//----------------------------------------------------------------------------------------------
//
// Inventory
//
// This is a simple App that connects to a paired TSL Reader and performs an Inventory
//
// This code shows the minimal code required to use the TSLAsciiCommand library. It has minimal
// error handling and does not necessarily implement all requirements of a well behaved iOS App
//
//
//----------------------------------------------------------------------------------------------


@interface TSLInventoryViewController ()
{
    NSArray * _accessoryList;

    TSLAsciiCommander *_commander;
    TSLInventoryCommand *_inventoryResponder;
    TSLBarcodeCommand *_barcodeResponder;

    int _minPower;
    int _maxPower;
}

@property (nonatomic, readwrite) UIColor *defaultSelectReaderBackgroundColor;
@property (nonatomic, readwrite) UIColor *defaultSelectReaderTextColor;
@property (nonatomic, readwrite) int transpondersSeen;
@property (nonatomic, readwrite) NSString *partialResultMessage;
@property (nonatomic, readwrite) NSDateFormatter *dateFormatter;

@end

@implementation TSLInventoryViewController

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];

    // Use a single AsciiCommander held in the AppDelegate
    _commander = ((TSLAppDelegate *)[[UIApplication sharedApplication]delegate]).commander;

    // This formatter will convert any timestamps received
    _dateFormatter = [[NSDateFormatter alloc] init];
    [_dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss"];
    [_dateFormatter setTimeZone:[NSTimeZone localTimeZone]];

    // Note: the weakSelf is used to avoid warning of retain cycles when self is used in Blocks
    __weak typeof(self) weakSelf = self;


    //
    // Performing an inventory could potentially take a long time if many transponders are in range so it is best to handle responses asynchronously
    //
    // The TSLInventoryCommand is also a TSLAsciiResponder for inventory responses and can have a transponderDataReceivedBlock
    // that is informed of each transponder as it is received

    // Create a TSLInventoryCommand
    _inventoryResponder = [[TSLInventoryCommand alloc] init];

    //
    // Use the TransponderData-based per transponder Block callback
    //
    _inventoryResponder.transponderDataReceivedBlock = ^(TSLTransponderData *transponder, BOOL moreAvailable)
    {
        // Append the transponder EPC identifier and RSSI to the results
        weakSelf.partialResultMessage = [weakSelf.partialResultMessage stringByAppendingFormat:@"Date: %@\nEPC:  %@\nFTID: %@\nIndx: %@\nPC:   %@\nCRC:  %@\nRSSI: %@\n\n",
                                         (transponder.timestamp == nil ) ? @"n/a" : [weakSelf.dateFormatter stringFromDate: transponder.timestamp],
                                         (transponder.epc == nil ) ? @"n/a" : transponder.epc,
                                         (transponder.fastTidData == nil) ? @"n/a" : [TSLBinaryEncoding toBase16String:transponder.fastTidData],
                                         (transponder.index == nil ) ? @"n/a" : [NSString stringWithFormat:@"%04X", transponder.index.unsignedIntValue ],
                                         (transponder.pc == nil) ? @"n/a" : [NSString stringWithFormat:@"%04X", transponder.pc.unsignedIntValue ],
                                         (transponder.crc == nil) ? @"n/a" : [NSString stringWithFormat:@"%04X", transponder.crc.unsignedIntValue ],
                                         (transponder.rssi == nil ) ? @"n/a" : [NSString stringWithFormat:@"%3d", transponder.rssi.intValue]
                                         ];

        weakSelf.transpondersSeen++;

        // If this is the last transponder add a few blank lines
        if( !moreAvailable )
        {
            weakSelf.partialResultMessage = [weakSelf.partialResultMessage stringByAppendingFormat:@"\nTransponders seen: %4d\n\n", weakSelf.transpondersSeen];
            weakSelf.transpondersSeen = 0;
        }

        // This changes UI elements so perform it on the UI thread
        // Avoid sending too many screen updates as it can stall the display
        if( !moreAvailable || weakSelf.transpondersSeen < 3 || weakSelf.transpondersSeen % 10 == 0 )
        {
            [weakSelf performSelectorOnMainThread: @selector(updateResults:) withObject:weakSelf.partialResultMessage waitUntilDone:NO];
            weakSelf.partialResultMessage = @"";
        }

    };

    // Pulling the Reader trigger will generate inventory responses that are not from the library.
    // To ensure these are also seen requires explicitly requesting handling of non-library command responses
    _inventoryResponder.captureNonLibraryResponses = YES;

    //
    // Use the responseBeganBlock and responseEndedBlock to change the colour of the reader button while a response is being received
    //

    // Remember the initial button colors
    self.defaultSelectReaderBackgroundColor = self.selectReaderButton.backgroundColor;
    self.defaultSelectReaderTextColor = self.selectReaderButton.titleLabel.textColor;

    _inventoryResponder.responseBeganBlock = ^
    {
        dispatch_async(dispatch_get_main_queue(),^
                       {
                           weakSelf.selectReaderButton.backgroundColor = [UIColor blueColor];
                           weakSelf.selectReaderButton.titleLabel.textColor = [UIColor whiteColor];
                       });
    };
    _inventoryResponder.responseEndedBlock = ^
    {
        dispatch_async(dispatch_get_main_queue(),^
                       {
                           weakSelf.selectReaderButton.backgroundColor = weakSelf.defaultSelectReaderBackgroundColor;
                           weakSelf.selectReaderButton.titleLabel.textColor = weakSelf.defaultSelectReaderTextColor;
                       });
    };

    // Add the inventory responder to the commander's responder chain
    [_commander addResponder:_inventoryResponder];

    //
    // Handling barcode responses is similar to the inventory
    //
    _barcodeResponder = [[TSLBarcodeCommand alloc] init];
    _barcodeResponder.barcodeReceivedDelegate = self;
    _barcodeResponder.captureNonLibraryResponses = YES;

    [_commander addResponder:_barcodeResponder];
    
    // No transponders seen yet
    _transpondersSeen = 0;

    _partialResultMessage = @"";

    // Set default power limits
    _minPower = [TSLInventoryCommand minimumOutputPower];
    _maxPower = [TSLInventoryCommand maximumOutputPower];
}


-(void)viewWillAppear:(BOOL)animated
{
    // Listen for change in TSLAsciiCommander state
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(commanderChangedState:) name:TSLCommanderStateChangedNotification object:_commander];
    
    // Update list of connected accessories
    _accessoryList = [[EAAccessoryManager sharedAccessoryManager] connectedAccessories];

    // Prepare and show the connected reader, if any
    [self initConnectedReader: _commander.isConnected];
    [self showConnectedReader:_commander.isConnected];
}

-(void)viewWillDisappear:(BOOL)animated
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - TSLBarcodeCommandTransponderReceivedDelegate methods

//
// Each barcode received from the reader is passed to this method
//
// Note: This is an asynchronous call from a separate thread
//
-(void)barcodeReceived:(NSString *)data
{
    NSString *message = [NSString stringWithFormat:@"BRCD: %@\n\n", data];
    [self performSelectorOnMainThread: @selector(updateResults:) withObject:message waitUntilDone:NO];
}


#pragma mark

//
// Add the given message to the bottom of the results area
//
-(void)updateResults:(NSString *)message
{
    self.resultsTextView.text = [self.resultsTextView.text stringByAppendingString:message];

    // Ensure the end of the new information is visible
    [self.resultsTextView scrollRangeToVisible:NSMakeRange(self.resultsTextView.text.length - 1, 1)];
}


-(void)commanderChangedState:(NSNotification *)notification
{
    // The connected state is indicated by the presence or absence of userInfo
    BOOL isConnected = notification.userInfo != nil;

    [self initConnectedReader: isConnected];
    [self showConnectedReader: isConnected];
}



#pragma mark - Reader Selection

//
// Segues for the controller
//
-(void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if( [segue.identifier isEqualToString:@"segueSelectReader"] )
    {
        UINavigationController *navController = (UINavigationController *)segue.destinationViewController;
        TSLSelectReaderViewController *selectReaderViewcontroller = (TSLSelectReaderViewController *)navController.viewControllers[0];
        selectReaderViewcontroller.delegate = self;
    }
}


//
// The delegate for the SelectReaderViewController
//
-(void)didSelectReaderForRow:(NSInteger)row
{
    [self dismissViewControllerAnimated:YES completion:^
    {
        // Update list of connected accessories
        self->_accessoryList = [[EAAccessoryManager sharedAccessoryManager] connectedAccessories];

        // Connect to the chosen TSL Reader
        if( self->_accessoryList.count > 0 )
        {
            // The row is the offset into the list of connected accessories
            EAAccessory *chosenAccessory = [self->_accessoryList objectAtIndex:row];
            [self->_commander connect:chosenAccessory];
        }
    }];
}


//
// Prepare the reader for use
//
-(void)initConnectedReader:(BOOL)isConnected
{
    if( isConnected )
    {
        // Ensure the reader is in a known (default) state
        // No information is returned by the reset command
        TSLFactoryDefaultsCommand * resetCommand = [TSLFactoryDefaultsCommand synchronousCommand];
        [_commander executeCommand:resetCommand];

        // Notify user device has been reset
        if( resetCommand.isSuccessful )
        {
            self.resultsTextView.text = [self.resultsTextView.text stringByAppendingString:@"Reader reset to Factory Defaults\n"];
        }
        else
        {
            self.resultsTextView.text = [self.resultsTextView.text stringByAppendingString:@"!!! Unable to reset reader to Factory Defaults !!!\n"];
        }

        // Get version information for the reader
        // Use the TSLVersionInformationCommand synchronously as the returned information is needed below
        TSLVersionInformationCommand * versionCommand = [TSLVersionInformationCommand synchronousCommand];
        [_commander executeCommand:versionCommand];
        TSLBatteryStatusCommand *batteryCommand = [TSLBatteryStatusCommand synchronousCommand];
        [_commander executeCommand:batteryCommand];

        // Determine the pop-Loq mode - if not an ePop-Loq Reader then the popLoqMode parameter will be 'Not Specified'
        TSLFactoryDefaultsCommand *fdCommand = [TSLFactoryDefaultsCommand synchronousCommand];
        fdCommand.readParameters = TSL_TriState_YES;
        [_commander executeCommand:fdCommand];

        // Display some of the values obtained
        self.resultsTextView.text = [self.resultsTextView.text stringByAppendingFormat:@"\n%-16s %@\n%-16s %@\n%-16s %@\n%-16s %@\n%-16s %@\n%-16s %@\n\n",
                                     "Manufacturer:", versionCommand.manufacturer,
                                     "Serial Number:", versionCommand.serialNumber,
                                     "Firmware:", versionCommand.firmwareVersion,
                                     "ASCII Protocol:", versionCommand.asciiProtocol,
                                     "Battery Level:", [NSString stringWithFormat:@"%d%%", batteryCommand.batteryLevel],
                                     "ePop-Loq Mode:", (fdCommand.popLoqMode == TSL_PopLoqMode_NotSpecified ? @"No ePop-Loq" : [TSLFactoryDefaultsCommand descriptionForPopLoqMode:fdCommand.popLoqMode])
                                     ];

        // Ensure new information is visible
        [self.resultsTextView scrollRangeToVisible:NSMakeRange(self.resultsTextView.text.length - 1, 1)];

        // Determine the maximum power level
        // This works for Readers of any region as the default is always maximum power
        TSLInventoryCommand *invQueryCommand = [TSLInventoryCommand synchronousCommand];
        invQueryCommand.resetParameters = TSL_TriState_YES;
        invQueryCommand.readParameters = TSL_TriState_YES;
        invQueryCommand.takeNoAction = TSL_TriState_YES; // no inventory is performed - just need parameter value responses

        // Execute the command
        [_commander executeCommand:invQueryCommand];

        //
        if( invQueryCommand.isSuccessful )
        {
            // The command was executed...
            _maxPower = invQueryCommand.outputPower;
            NSLog(@"Maximum allowed power: %d dBm", _maxPower);
        }
        else
        {
            // Command should not fail unless connection was lost -
            NSLog(@"Unable to determine upper power limit, defaulting to: %d dBm", _maxPower);
        }

        [self configureInventory];
        [self outputPowerChanged:self];
    }
}


//
// Use a no-action inventory command to configure the inventory information returned
//
-(void)configureInventory
{
    TSLInventoryCommand *configureInventoryCommand = [TSLInventoryCommand synchronousCommand];
    // Ensure command uses defaults for the non-specified parameters
    configureInventoryCommand.resetParameters = TSL_TriState_YES;
    configureInventoryCommand.takeNoAction = TSL_TriState_YES;

    [self configureDefaultInventoryParameters:configureInventoryCommand];
    [self configureUserInventoryParameters:configureInventoryCommand];

    [_commander executeCommand:configureInventoryCommand];

    if( !configureInventoryCommand.isSuccessful )
    {
        NSLog(@"!!! Failed to configure the reader inventory command !!!");
    }
}


//
// Set the parameters that are not alterable by the user on the given inventory command
//
-(void)configureDefaultInventoryParameters:(TSLInventoryCommand *)command
{
    // Request all available data
    command.includeDateTime = TSL_TriState_YES;
    command.includeEPC = TSL_TriState_YES;
    command.includeIndex = TSL_TriState_YES;
    command.includePC = TSL_TriState_YES;
    command.includeChecksum = TSL_TriState_YES;
    command.includeTransponderRSSI = TSL_TriState_YES;

    command.useFastId = self.fastIdSwitch.isOn ? TSL_TriState_YES : TSL_TriState_NO;

}


//
// Set the parameters that can be altered by the user on the given inventory command
//
-(void)configureUserInventoryParameters:(TSLInventoryCommand *)command
{
    // Use teh Impinj FastId option when requested
    command.useFastId = self.fastIdSwitch.isOn ? TSL_TriState_YES : TSL_TriState_NO;

    // Use the chosen power level
    int value = [self outputPowerFromSliderValue:self.outputPowerSlider.value];
    command.outputPower = value;
}


//
// Display basic information about the reader
//
-(void)showConnectedReader:(BOOL)isConnected
{
    if( isConnected )
    {
        // Display the serial number of the successfully connected unit
        [self.selectReaderButton setTitle:_commander.connectedAccessory.serialNumber forState:UIControlStateNormal];
    }
    else
    {
        [self.selectReaderButton setTitle:@"Tap to select reader..." forState:UIControlStateNormal];
    }
}


#pragma mark - Actions

//
// Issue an asynchronous Inventory scan
//
- (IBAction)performInventory
{
    if( _commander.isConnected )
    {
        // Use an asynchronous TSLInventoryCommand
        // i.e. let the same responder that catches the triggered inventory catch the responses
        TSLInventoryCommand *invCommand = [[TSLInventoryCommand alloc] init];

        [self configureUserInventoryParameters:invCommand];

        [_commander executeCommand:invCommand];
    }
}

//
// Issue a synchronous barcode scan
//
- (IBAction)performBarcodeScan:(id)sender
{
    if( _commander.isConnected )
    {
        // Use the TSLBarcodeCommand
        TSLBarcodeCommand *barCommand = [TSLBarcodeCommand synchronousCommand];
        barCommand.barcodeReceivedDelegate = self;

        [_commander executeCommand:barCommand];
    }
}

- (IBAction)clearResults
{
    self.resultsTextView.text = @"";
}


#pragma mark - Fast ID switch

- (IBAction)fastIdChanged:(id)sender
{
    [self updateReaderInventoryConfiguration];
}


#pragma mark - Output Power Control



-(int)outputPowerFromSliderValue:(float)value
{
    int range = _maxPower - _minPower;

    return (int)(value * range + _minPower + 0.5);
}


- (IBAction)outputPowerChanged:(id)sender
{
    self.outputPowerLabel.text = [NSString stringWithFormat:@"%2d", [self outputPowerFromSliderValue:self.outputPowerSlider.value]];
}

- (IBAction)outputPowerEditingDidEnd:(id)sender
{
    int value = [self outputPowerFromSliderValue:self.outputPowerSlider.value];
    self.resultsTextView.text = [self.resultsTextView.text stringByAppendingFormat:@"Output level changed to: %2d\n\n", value];
    [self updateReaderInventoryConfiguration];
}

//
// Update the reader with all User-modifiable inventory parameters
//
-(void)updateReaderInventoryConfiguration
{
    if( _commander.isConnected )
    {
        TSLInventoryCommand *command = [TSLInventoryCommand synchronousCommand];
        command.takeNoAction = TSL_TriState_YES;

        [self configureUserInventoryParameters:command];

        [_commander executeCommand:command];

        if( !command.isSuccessful )
        {
            NSLog(@"!!! Failed to update the reader configuration !!!");
        }
    }
}

@end
