// NeuronTracker (aka SmallArena GCaMP Tracking)
// Dirk Albrecht, Johannes Larsch
// 
// v1.0 DRA/JL March, 2013
//
// v1.1 DRA
//  - attempt to clean up file locations
//
// v.1.11 DRA - add comments
// v.1.12 DRA - streamline input variables
//                new TrackSettings array: 


macro "NeuronTracking v1.11 [t] Action Tool - Cg902T3f18N" {

// Obtain Tracking Settings

  // Track setting Defaults are read from txt file -- ** optional, add a GUI to input parameters **
  // 
  //   Place tracking settings files in the ImageJ/Fiji app folder
  //
  currentdir = getDirectory("current");                                     // get current directory
  call("ij.io.OpenDialog.setDefaultDirectory", getDirectory("imagej"));     // change default to imagej dir
  //call("ij.io.OpenDialog.setLastName","Track*.txt");     // change default to imagej dir
  TrackSettingfile = File.openDialog("Select a Track Settings file")
  //TrackSettingfile = File.openDialog("Select a Track Settings file", getDirectory("imagej"), "Track*.txt");
  //TrackSettingfile = call("ij.io.OpenDialog.OpenDialog","Select a Track Settings file", getDirectory("imagej"), "Track*.txt");       
  call("ij.io.OpenDialog.setDefaultDirectory", currentdir);                 // return to prior directory
  //TrackSettingfile="C:\\Fiji.app\\TrckSett_AWC_5x_4pxSq_AdaptMoving.txt";
  
  MAX_ANIMALS = 25;                                               // maximum animals, for preallocaing arrays               
  BG_RING_OUT = 1.5;                                              // outer vs inner diameter for background ring
  
  TrackSetting=newArray(MAX_ANIMALS);                             // initialize settings array 
  TrackSetting=ReadSettings(TrackSetting,TrackSettingfile);       // read settings from file

  // Define variables from Track Settings
  //
  animal = TrackSetting[0];             // animal # (no longer used) 
  lower = TrackSetting[1];              // lower intensity threshold                   
  upper = 65535;                        // upper intensity threshold 
  searchDia = TrackSetting[2];          // diameter of search window for tracking
  bgRingDia = TrackSetting[3];          // inner diameter of background ring (inner, outer = 1.5x)
  sqsize = TrackSetting[4];             // size of square for intensity measurement of neuron
  maxsize = TrackSetting[5];            // upper limit of particle size for tracking
  minsize = TrackSetting[6];            // lower limit of particle size for tracking
  expandAllow = TrackSetting[7];        // limit of allowed expansion of search window for tracking
  useTracking = TrackSetting[8];        // update location if integration box, or keep static
  velocityPredict = TrackSetting[9];    // use velocity prediction to update search window


  // Default variables. not relevant for tracking function

  FrameForNeuronClick = 2;              // choose a frame when fluorescence is expected high to facilitate neuron selection
  animalThreshold = newArray(MAX_ANIMALS);       // array of animal specific lower thresholds
  trackFolder = 1;                      // 1: track folder; 0: track open file


//-------------------------------------------------
// Define the tracking session, either multiple videos in a folder, or a single video.
//   Check if images open.
//   if images are open, track the single open movie.
//   otherwise, ask for a directory for batch tracking
  
   
  if (nImages == 0) {                       // if there are no open images...
  
    trackFolder = 1;                        // set to track a folder
    //dir="e:\\f\\20130205_n2_Ky121_1_N2_crossadapt\\";
    dir = getDirectory("Choose a directory of .tif videos for tracking");     
                                            // get folder name containing .tif video files 
    list = getFileList(dir);                // get all files in directory...
    Array.sort(list);                       // ...and sort them
    newlist = newArray(list.length);
    k = 0;
    for (i = 0; i < list.length; i++)  {    // check each file for .tif ending
      if (endsWith(list[i], ".tif")) {
        newlist[k] = list[i];
        k++;
      }
    }
    list = Array.trim(newlist, k);          // "list" contains all .tif files in chosen directory

    // Allow selection of the starting and ending video number
    //
    if (list.length > 1) {
    	startFile = getNumber("found "+list.length+" files, at what movie do you want to start tracking?", 1); startFile = startFile-1;
    	endFile = getNumber("found "+list.length+" files, at what movie do you want to end tracking?", list.length); endFile = endFile-1;
    } else {
    	startFile = 0;
    	endFile = 0;
    }
    open(dir + list[startFile]);            // open the first video 
  
  } else {                                  // if there are open videos, then just track the one.
  
    trackFolder = 0;                        // continue single movie tracking    
   
  }

	if (getVersion>="1.37r") setOption("DisablePopupMenu", true);  // this allows right-mouse-button to work


//-------------------------------------------------
// Get x-y coordinates of each neuron, either from position file or via manual selection
// 
// if position files are found, ask if they should be used
//    there are 2 types of position files
//    'PosFile' has positions in movie that was last tracked in current folder
//    'moviePosFile' is created for each movie during tracking

  mainid = getImageID();                                  // image identifier
  title = getTitle();                                     // image title
  titleNoExt=substring(title,0,lengthOf(title)-4);        // image title without ".tif" extension

  dir = getDirectory("image");                            // current image directory  
  pathnoext = dir+substring(title,0,lengthOf(title)-4);   // current image directory with image name, no extension

  setSlice(FrameForNeuronClick);                          // move to define frame (slice)
  run("Select None");                                     // clear any selections
  setThreshold(lower, upper);                             // set default thresholds
  updateDisplay();                                  

  moviePosFile = dir+titleNoExt+"_Pos.txt";               // movie position file name
  PosFile=dir+"initialPos.txt";                           // initial position file name

  if (File.exists(moviePosFile) == 1) {                   // check if movie position file exists    
    readfile = moviePosFile;
  } else if (File.exists(PosFile) == 1) {                 // check if an initial position file exists
    readfile = PosFile;
  } else {
    readfile = "none";
  }
  
  // if existing neuron positions are chosen, read animal info from position file
  if (readfile!="none") { 
    xpAll = ReadAnimalInfo(readfile,"x","y");
    ypAll = ReadAnimalInfo(readfile,"y","a");
    animalThreshold = ReadAnimalInfo(readfile,"t","f");
    animalRedFlag = ReadAnimalInfo(readfile,"f","g");
    animalTracking = ReadAnimalInfo(readfile,"g","end");

    // temporarily draw rectangles on neuron positions
    for (animal=0; (animal < xpAll.length); animal++) {
      xc = xpAll[animal]; 
      yc = ypAll[animal];
      makeRectangle(xc - sqsize/2, yc - sqsize/2, sqsize, sqsize);
      run("Add Selection...", "stroke=yellow width=1 fill=0");
      print("x",xc,"y",yc,"a",animal,"t",animalThreshold[animal],"f",animalRedFlag[animal],"g",animalTracking[animal]);
    }
  
    animal++;
    firstAnimal=0;

    // Ask if these existing positions should be used
    useSavedPos = "";
    if (readfile == moviePosFile) {
      Dialog.create("Positions found for current movie");
    } else {
      Dialog.create("Positions found for current folder");
    }
    Dialog.addChoice("Use saved Positions", newArray("yes", "no", "yes and add more"));
    Dialog.show();
    useSavedPos = Dialog.getChoice();
    
    if (useSavedPos != "yes") { 
      readfile = "none";
    }
  }

  // get neuron positions manually if no posFiles found or not wanted
  if (readfile=="none") {

    // how many animals have been tracked for this movie already? (check filenames for "an#.txt" files)
    if (useSavedPos == "yes and add more") {
    	firstAnimal=-1;
      do {
        firstAnimal++;
        logname = pathnoext+".an"+firstAnimal+".txt";
      } while (File.exists(logname));                       // "firstAnimal" now is the number of the first animal to track
    } else if (useSavedPos == "") {  
    	xpAll = newArray(MAX_ANIMALS);                        // initialize for each animal x, y, etc.
    	ypAll = newArray(MAX_ANIMALS);
    	animalThreshold = newArray(MAX_ANIMALS);
    	animalRedFlag = newArray(MAX_ANIMALS);
    	animalTracking = newArray(MAX_ANIMALS);
    }
    
    doneWithPicking = 0;

    for (animal=firstAnimal; !doneWithPicking; animal++) {  // loop through manual clicking on each neuron, and logging x,y,threshold to file
      print(animalThreshold[animal]);
      if (animalThreshold[animal] == 0) animalThreshold[animal] = lower;
      setThreshold(animalThreshold[animal], upper);
      showStatus("Select center point of the neuron:"); 

      do {
        updateDisplay();  
        getCursorLoc(xc, yc, z, flags);                     // get xy mouse position and button press info  
        doneWithPicking = (flags==4);                       // right-click mouse (flag = 4) to end selections
        getThreshold(lower, upper);                         // get the current threshold limits (which can be changed by the user)
        animalThreshold[animal] = lower;                    // ...and log the lower bound
        wait(50);
        a = (flags != 16);                                  // if NO left-click (flag = 16),
        b = !doneWithPicking;                               // and not ready to end,
        c = a && b;
      } while (c);                                          // then continue waiting for input
      
    	//animalThreshold[animal] = lower;                    
      animalRedFlag[animal] = 0;														
      animalTracking[animal] = useTracking;
      xpAll[animal] = xc; ypAll[animal] = yc;               // log to animal x, y arrays
      if (b) print("x",xc,"y",yc,"a",animal,"t",lower,"f",0,"g",1);  // log the animal data, unless it's the end
      
      makeRectangle(xc - sqsize/2, yc - sqsize/2, sqsize, sqsize);   // label the animal and number
      run("Add Selection...", "stroke=green width=1 fill=0");
      
      makeRectangle(xc + sqsize/2, yc - sqsize/2, 24, 18);
      run("Labels...", "color=white font=12 show use draw");
      run("Properties... ", "name="+animal);
      run("Add Selection...", "stroke=black width=0 fill=0");

      slice = getSliceNumber();
      wait(1000);
    }                                                       // end loop per animal/neuron selected
    
  }                                                         // end manual selection of neurons

  selectWindow(title); 

//-------------------------------------------------
//
//   Begin tracking loops
//

  if (trackFolder==1) {                                     // if operating on several videos at once, 

    AnimalsToTrack = animal-1;                              // total number of animals to track (begins with 0)
    close();                                                // close video used to select neurons and begin loop with a clear workspace

    //**************** BIG LOOP through each movie file ***********************
    //
    
    for (i = startFile; i <= endFile; i++) {                // start looping through from first movie
  
      open(dir + list[i]);                                  // open current video file

      run("Set Scale...", "distance=0");                    // clear any spatial scaling, so all operations occur by pixels
  
      title = getTitle();                                   // get title (file) name
      titleNoExt=substring(title,0,lengthOf(title)-4);      // without ".tif" extension
      moviePosFile = dir+titleNoExt+"_Pos.txt";             // define the movie position filename

      script =                                              // set position of movie window
        "lw = WindowManager.getFrame('"+title+"');\n"+
          "if (lw!=null) {\n"+
          "   lw.setLocation(20,20);\n"+
          "}\n";
      eval("script", script); 

      script =                                              // set position of log window
        "lw = WindowManager.getFrame('Log');\n"+
          "if (lw!=null) {\n"+
          "   lw.setLocation(10,800);\n"+
          "   lw.setSize(800, 200)\n"+
          "}\n";
      eval("script", script); 

      // save previous neuron endPositions
      // save to initialPos.txt and video specific moviePos.txt

      selectWindow("Log");                                  // select Log window
      print("\\Clear");                                     // and clear it
      
      // Now, print animal position info to Log window
      
      for (animal = firstAnimal; animal < AnimalsToTrack; animal++) {   
        print("x",xpAll[animal],"y",ypAll[animal],"a",animal,"t",animalThreshold[animal],"f",animalRedFlag[animal],"g",animalTracking[animal]);
      }

      // and save it to the movie position file, and overwrite the initial position file also
      //   (this all seems odd below, but presumably was needed to ensure files were saved. perhaps revisit and code better)
      selectWindow("Log");
      wait(150); //for some reason, needs long delay here to work
      selectWindow("Log");
      wait(150);
      saveAs("Text",PosFile);
      selectWindow("Log");
      wait(150);
      selectWindow("Log");
      wait(150);
      saveAs("Text",moviePosFile);
      print("\\Clear");                                     // now clear the log window 

      selectWindow(title);                                  // return to the image window
      updateDisplay();

      //------------------------
      //
      //  
      for (animal=firstAnimal; animal<AnimalsToTrack; animal++) {   
        setThreshold(animalThreshold[animal], upper);
        updateDisplay();
        xc = xpAll[animal]; 
        yc = ypAll[animal];
    
        // update TrackSetting variable with info for this animal before calling the tracker
        TrackSetting[0] = animal;
        TrackSetting[1] = animalThreshold[animal];
        TrackSetting[2] = searchDia;
        TrackSetting[3] = bgRingDia;
        TrackSetting[4] = sqsize;
        TrackSetting[5] = maxsize;
        TrackSetting[6] = minsize;
        TrackSetting[7] = expandAllow;
        TrackSetting[8] = animalTracking[animal];
        TrackSetting[9] = velocityPredict;
        TrackSetting[10] = animalRedFlag[animal];
        TrackSetting[11] = xc;
        TrackSetting[12] = yc;

        setSlice(1);
        TrackSetting = SmallArenaTrackerBatch(TrackSetting);      // call tracking function *************
                                                            //   this can update the settings by user adjustment, so
                                                            //   update the relevant positions xc, yc, and threshold (lower)
                                                            //   and any red flags
                                                            
        lower = TrackSetting[1];                            // update any settings made during tracking
        xc = TrackSetting[11];
        yc = TrackSetting[12];
        animalRedFlag[animal] = TrackSetting[10];
        animalTracking[animal] = TrackSetting[8];
        animalThreshold[animal] = lower;
        xpAll[animal] = xc; ypAll[animal] = yc;
        print(xc,yc);
        
      }                                                     // end animal tracking loop 
      
      selectWindow(title); close();                         // close that video, and move to the next...
      animal=0;
      
    }  // *************** end of big loop over all video files ***************
    
  } else if (trackFolder==0) {                              // if there was only one open video file, then just track it...
                                                            //   (this is mainly for debugging)
    animal=0;
    xc = xpAll[animal]; 
    yc = ypAll[animal];
    //getThreshold(lower, upper);
    //animalThreshold[animal] = lower;
    setThreshold(animalThreshold[animal], upper);

    // update TrackSettng variable with info for this animal before calling the tracker
    TrackSetting[0] = animal;
    TrackSetting[1] = animalThreshold[animal];
    TrackSetting[2] = searchDia;
    TrackSetting[3] = bgRingDia;
    TrackSetting[4] = sqsize;
    TrackSetting[5] = maxsize;
    TrackSetting[6] = minsize;
    TrackSetting[7] = expandAllow;
    TrackSetting[8] = animalTracking[animal];
    TrackSetting[9] = velocityPredict;
    TrackSetting[10] = animalRedFlag[animal];
    TrackSetting[11] = xc;
    TrackSetting[12] = yc;
    setSlice(1);

    selectWindow("Log");
    print("start tracking");
    TrackSetting=SmallArenaTrackerBatch(TrackSetting)
  }

} //end macro NeuronTracking [t]


//-----------------------------------------------------------------------
//
//    FUNCTIONS
//
//-----------------------------------------------------------------------

//-----------------------------------------------------------------------
// ReadSettings parses the Tracking Settings .txt file to populate the TrackSetting array

function ReadSettings(TrackSetting,file) {
  //file="C:\\TrckSett_awa_5x_6pxSq.txt"
  string = File.openAsString(file);
  xlines = split(string, "\n");
  n_xlines = lengthOf(xlines);

  for (n=0; n<n_xlines; n++) {
    TrackSetting[n] = substring(xlines[n],0,indexOf(xlines[n],"//")-1);
  }

  return TrackSetting;
}

//-----------------------------------------------------------------------
// ReadAnimalInfo parses animal information string to populate selected values (separated by ID1 and ID2 characters)

function ReadAnimalInfo(PosFile,ID1,ID2) {

  string = File.openAsString(PosFile);
  lines = split(string, "\n");
  n_lines = lengthOf(lines);
  //AnimalInfo = newArray(n_lines);
	AnimalInfo = newArray(MAX_ANIMALS);

  for (n=0; n<n_lines; n++) {
    if (ID2=="end") {
      AnimalInfo[n] = substring(lines[n],indexOf(lines[n],ID1)+2);
    } else {
      AnimalInfo[n] = substring(lines[n],indexOf(lines[n],ID1)+2,indexOf(lines[n],ID2)-1);
    }
  }

  return AnimalInfo;
}


//-------------------------------------------------------
// SmallArenaTrackerBatch is the main neuron tracking function
//  this version of the tracker can be called once the neuron positions are known, via the TrackSetting array

function SmallArenaTrackerBatch(TrackSetting) {

  // collect track position information

  animal =      TrackSetting[0];
  lower =       TrackSetting[1];
  searchDia =   TrackSetting[2];
  bgRingDia =   TrackSetting[3];
  sqsize =      TrackSetting[4];
  maxsize =     TrackSetting[5];
  minsize =     TrackSetting[6];
  expandAllow = TrackSetting[7];
  useTracking = TrackSetting[8];
  velocityPredict = TrackSetting[9];
  redFlag =     TrackSetting[10];
  xc =          TrackSetting[11];
  yc =          TrackSetting[12];

  print(xc,yc);

  // Get image information
  mainid = getImageID();
  title = getTitle();
  dir = getDirectory("image");
  pathnoext = dir+substring(title,0,lengthOf(title)-4);

  // Initialize variables
  area = 0; maxint = 0; intdens = 0; x = xc; y = yc; intsub = 0; 
  sqintdens =0; sqintsub =0; sqarea = 0; avg = 0; dx = 0; dy = 0;
  X = newArray(nSlices);                                    // variables for plotting graphs only
  Y = newArray(nSlices);
  Int1 = newArray(nSlices);
  Int2 = newArray(nSlices);
  BgMed = newArray(nSlices);
  Avg = newArray(nSlices);
  xp = xc; yp = yc;                                         // xp, yp = prior centroid

  // Clear the Log window and print header info
  print("\\Clear");
  print("Slice,xc,yc,intdens,intsub,bgmedian,maxint,area,x,y,sqintdens,sqintsub,sqarea,threshold,animal,redFlag");

  selectWindow(title);
  setThreshold(lower, 65535);                               // Set threshold for this animal

  // LOOP through each frame of the image stack
  //
  for (slice=1; slice<=nSlices; slice++)  {                 // starting at frame 2 is a legacy act, as first frame had no
                                                            // illumination. Verify that this is still needed; changed to 1.

    setSlice(slice);                                        // go to current frame (slice)

    // Allow manual pausing via spacebar
    selectWindow(title); // *** this command slows down tracking A LOT! But it's necessary to detect keyDown reliably!

    anyKeyDown = 0;
    anyKeyDown = isKeyDown("space") || isKeyDown("shift") || isKeyDown("alt"); // avoiding if statements in loop
    if(anyKeyDown) {

      if (isKeyDown("space")) {                             // SPACE bar pressed for manual repositioning
        showStatus("Select center point of the neuron:"); 
        do {
          getCursorLoc(xc, yc, z, flags);
          wait(50);
        } while (flags != 16);                              // flag 16 = left mouse button
        xp = xc; yp = yc;
        slice = getSliceNumber();
        
        // Update threshold and remove any upper limit
        getThreshold(lower, upper); wait(100);
        setThreshold(lower, 65535);
      }

      // Allow stationary tracking via 'shift' toggle       
      if (isKeyDown("shift")) {                             // SHIFT key toggles "useTracking" flag 
        wait(400);                                          // add delay to prevent double toggles        
        useTracking = !useTracking;
      }

      // Allow flagging via 'alt'
      if (isKeyDown("alt")) {                               // ALT key toggles "redFlag" flag 
        wait(400);
        redFlag = !redFlag;
      }

    }                                                       // End key checking test

    //----------------------------------------------------------
    //  Update the neuron position search box, if Tracking is to be used. Otherwise, keep it stationary
    //
  
    if (useTracking == 1) {

      makeOval(xc - searchDia/2, yc - searchDia/2, searchDia, searchDia);       // Select circular search region centered on x,y centroid
  
      // Analyze thresholded pixels within search area
    
      run("Set Measurements...", "area min centroid center integrated slice limit redirect=None decimal=3");
      //run("Analyze Particles...", "size="+minsize+"-"+maxsize+" circularity=0.00-1.00 show=Nothing display exclude clear slice");
      run("Analyze Particles...", "size="+minsize+"-"+maxsize+" circularity=0.00-1.00 show=Nothing display clear slice");

      if (nResults == 1) {                                  // Ideally, only one object is found within size limits. 
        xc = getResult("XM", 0);                            // Collect data: x-center of mass
        yc = getResult("YM", 0);                            //               y-center of mass
        area = getResult("Area", 0);                        //               thresholded area (pixels^2)
        maxint = getResult("Max", 0);                       //               maximum intensity
        intdens = getResult("IntDen", 0);                   //               integrated density (sum of thresholded pixel values)
        x = getResult("X", 0);                              //               x-centroid
        y = getResult("Y", 0);                              //               y-centroid
        avg = intdens / area;                               //               average intensity
      
      } else if (nResults > 1) {                            // If more than one object is found within size limits, choose the biggest. 
        biggestArea = 0;
        for (res=0; res < nResults; res++) {
          resArea = getResult("Area", res);
          if (resArea > biggestArea) {
            biggestArea = resArea;
            biggestAreaPos = res;
          }
        }

        xc = getResult("XM", biggestAreaPos );              // Collect data just for the biggest area, as above.
        yc = getResult("YM", biggestAreaPos );
        area = getResult("Area", biggestAreaPos );
        maxint = getResult("Max", biggestAreaPos );
        intdens = getResult("IntDen", biggestAreaPos );
        x = getResult("X", biggestAreaPos );
        y = getResult("Y", biggestAreaPos );
        avg = intdens / area;
      
      } else {                                              // If no object is found within size limits, expand the search region
        expand = 0;
        do {  
          expand++;                                         // increment the expansion step up to the allowed number (expandAllow)
                                                            // of pixels, and update the search region. 
          makeOval(xc - searchDia/2 - expand, yc - searchDia/2 - expand, searchDia+2*expand, searchDia+2*expand);
          //run("Analyze Particles...", "size="+minsize+"-"+maxsize+" circularity=0.00-1.00 show=Nothing display exclude clear slice");
          run("Analyze Particles...", "size="+minsize+"-"+maxsize+" circularity=0.00-1.00 show=Nothing display clear slice");
        
        } while ((nResults < 1) && (expand <= expandAllow));  // continue expanding until 1 acceptable object is found and limit isn't hit 
      
        if (nResults == 1) {                                // if one object is found, then log the data as above. 
          xc = getResult("XM", 0);
          yc = getResult("YM", 0);
          area = getResult("Area", 0);
          maxint = getResult("Max", 0);
          intdens = getResult("IntDen", 0);
          x = getResult("X", 0);
          y = getResult("Y", 0);
          avg = intdens / area;
        
        } else {                                            // Otherwise, give up, stop tracking, and wait for user input to click
                                                            // on a new neuron position (perhaps after adjusting the threshold)
          makeRectangle(xc - sqsize/2, yc - sqsize/2, sqsize, sqsize);      // draw the prior position
          showStatus("Select center point of the neuron:"); 
          do {
            getCursorLoc(xc, yc, z, flags);
            wait(50);
          } while (flags != 16);                            // left mouse button = 16        
          xp = xc; yp = yc;
          slice = getSliceNumber();

          // Reset the threshold and remove any upper threshold limit
          getThreshold(lower, upper); wait(100);
          setThreshold(lower, 65535);
        }
      
      }
    }      // -------------  end of loop that updates the neuron position within the tracking region ----------                                                 

    //-------------------------------------------------
    //   Get neuron fluorescence data  
    // 
  
    // set small region around neuron center, square of edge size "sqsize"
    makeRectangle(xc - sqsize/2, yc - sqsize/2, sqsize, sqsize);
  
    run("Clear Results");                                   // Clear Results window
    setThreshold(lower, 65535);                             // ensure no upper threshold limit
  
    // get neural fluorescence:
    //   sqintdens = integrated density of the square region over the neuron, or the sum of all pixel values
    //   sqarea = area in pixels (= sqsize^2)
  
    run("Set Measurements...", "area min centroid center integrated slice redirect=None decimal=3");
    run("Measure");                                         // measure integrated density and area
    if (nResults == 1) {
      sqarea = getResult("Area", 0);
      sqintdens = getResult("IntDen", 0);
    }
    run("Add Selection...", "stroke=yellow width=1 fill=0");  // display yellow box as overlay
    Overlay.setPosition(slice);

    // get background intensity using an annulus around the neuron
    //   bgavg = average intensity of background annulus
    //   bgmedian = median intensity of background annulus
    //   intsub = integrated density of neuron object - bgmedian*pixels in neuron object
    //   sqintsub = integrated density of neuron box - bgmedian*pixels in neuron box
  
    // define the background annulus region (cirlular outer region, then "alt" removes the inner circle)
    makeOval(xc - bgRingDia/2*BG_RING_OUT, yc - bgRingDia/2*BG_RING_OUT, bgRingDia*BG_RING_OUT, bgRingDia*BG_RING_OUT);
    setKeyDown("alt");                                      
    makeOval(xc - bgRingDia/2, yc - bgRingDia/2, bgRingDia, bgRingDia);

    run("Clear Results");                                   // Clear results window and measure background parameters  
    run("Set Measurements...", "area mean min median slice redirect=None decimal=3");
    run("Measure");
    if (nResults == 1) {
      bgavg = getResult("Mean", 0);
      bgmedian = getResult("Median", 0);
      intsub = intdens - (area * bgmedian);
      sqintsub = sqintdens - (sqarea * bgmedian);
    }

    // log the data to the Log window
    print(slice+","+xc+","+yc+","+intdens+","+intsub+","+bgmedian+","+maxint+","+area+","+x+","+y+","+sqintdens+","+sqintsub+","+sqarea+","+lower+","+animal+","+redFlag+","+useTracking);
  
    //X[slice-1] = xc;                                        // Build some arrays for displaying the data
    //Y[slice-1] = yc;
    //Int1[slice-1] = intsub;
    Int2[slice-1] = sqintsub;
    BgMed[slice-1] = bgmedian*sqarea;
    //Avg[slice-1] = avg;
  
    //-----------------------------------------------------
    // Velocity prediction
    //   For moving animals, the next search region can be adjusted according to current velocity (or fraction thereof)
    
    if (velocityPredict >= 0) {
      dx = xc-xp; dy = yc-yp;                               // get velocity (dx, dy) 
      xc = xc + dx/2; yc = yc+dy/2;                         // update current neuron position via velocity
    } 
    
    xp = xc; yp = yc;                                       // set prior centroid position
    
  }     // --------------- END large loop through each frame of video ----------------------


  //--------------------------------------------------------
  // Display the results 
  
  // plot of x, y, position over time
  //Plot.create("Position", "Frame", "Pixels", X);
  //Plot.setLimits(0, nSlices, 0, 512);
  //Plot.setColor("red");
  //Plot.add("line", Y);
  //Plot.setColor("blue");

  // plot of "sqintsub" -- integrated intensity of neuron box - median value of background annulus 
  Plot.create("Integrated intensity", "Frame", "Sq. Intensity");
  Plot.setColor("black");
  Plot.add("line", Int2);
  Plot.setColor("red");
  Plot.add("line", BgMed);
  Plot.setLegend("Intensity - BgMedian\tBgMedian", "top-right");
  Plot.setLimitsToFit();
  Plot.show();
  setLocation(5, 400);

  // Log the data to a text file
  selectWindow("Log");
  logname = pathnoext+".an"+animal+".txt";

  action = "";
  if (!File.exists(logname)) {                              // check if file exists; if not write the data
    wait(50);                                               // again, weird delays to ensure file writing is successful. 
    selectWindow("Log");
    wait(150);
    selectWindow("Log");
    wait(150);
    saveAs("Text",logname);
  } else {                                                  // if a file already exists, ask to overwrite or to log as a new animal
    Dialog.create("Log file already exists");
    Dialog.addChoice("Choose:", newArray("Overwrite", "New Animal"));
    Dialog.show();
    action = Dialog.getChoice();
    if (action!="Overwrite") {
      do {
      animal++;
      logname = pathnoext+".an"+animal+".txt";
      } while (File.exists(logname));
    }
    
    selectWindow("Log");                                    // again, weird delays to ensure file writing is successful. 
    wait(150);
    selectWindow("Log");
    wait(150);
    saveAs("Text",logname);
  }
  
  print(action);                                            // log some progress activity
  print("Saved to logfile: "+logname);
  
  selectWindow("Integrated intensity");                     // clear the intensity plot
  wait(100);
  close();
  
  selectWindow(title);

  TrackSetting[1]=lower;                                       // Update some track settings...
  TrackSetting[11]=xc;
  TrackSetting[12]=yc;
  TrackSetting[10]=redFlag;
  TrackSetting[8]=useTracking;

  return TrackSetting;                                         // ...and return it to the main code

} // end function SmallArenaTracker
