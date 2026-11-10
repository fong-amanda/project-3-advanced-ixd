## Which device

- **iPhone 16 Pro**, or any iPhone with a LiDAR scanner (iPhone 12 Pro or newer Pro models), running **iOS 18** or later.

## How to open it

You'll need a Mac with **Xcode 16** or later (free from the App Store; open it once and let it install the iOS components). 

1. Download the repo (**Code › Download ZIP**, then unzip, or clone it) and double-click `ios/SharedSpace.xcodeproj`. Xcode downloads the supabase-swift package the first time it opens
   -  If Xcode doesn't open, open Xcode yourself. In the welcome window, click **Open…**, go to the unzipped folder, open the **ios** folder, select **SharedSpace.xcodeproj**, and click **Open**.

   The first time the project opens, Xcode downloads the supabase-swift package. Wait for it to finish before running the app.

### Option A: on a Mac, in the Simulator

2. In Xcode's toolbar, click the run destination menu (next to the SharedSpace scheme) and choose an iPhone Simulator, such as **iPhone 16 Pro**.
   
3. Click the **Run** button (▶) in the top-left corner of Xcode, or press **Command (⌘) + R**. The Simulator opens and launches the app. The first build takes a minute or two.

### Option B: on your iPhone
2. **Add your Apple ID to Xcode:** in the menu bar, choose **Xcode › Settings › Accounts**, click **+**, choose **Apple ID**, and sign in.
3. **Set up signing:** in the left sidebar, click **SharedSpace** with the blue icon at the top, then **SharedSpace** under **TARGETS**.
   - In the **General** dropdown, change **Bundle Identifier** from `com.example.sharedspace` to something unique, like `com.yourname.sharedspace`.
   - Switch the dropdown to **Signing & Capabilities**, open the **Signing** section, check **Automatically manage signing**, and choose **Your Name (Personal Team)** under **Team**.
4. **Connect your iPhone** with the cable, unlock it, and tap **Trust** if it asks "Trust This Computer?"
5. **Choose your iPhone** in Xcode's run destination menu, at the top of the list. If Xcode says it's preparing the phone, let it finish. If Signing & Capabilities shows a warning about no devices or no profiles, click **Try Again** now.
6. **Turn on Developer Mode** on the iPhone: Settings › Privacy & Security › **Developer Mode**, then restart the phone and tap **Turn On** when asked.
7. Click **Run** (▶) or press **Command (⌘) + R**. If your Mac asks for permission for "codesign" to use your keychain, enter your Mac password and click **Always Allow**.
8. **Trust yourself as a developer** the first time the app opens: on the iPhone, go to Settings › General › **VPN & Device Management**, tap your Apple ID under **Developer App**, and tap **Trust**. The phone must be online for this, and a VPN can block it, so turn any VPN off first. Then open Shared Space from your home screen and allow camera access when asked.

## What's faked
- **3D dollhouse redesign:** [not built yet]
- **Live AR view of a design in the room:** [not built yet]
- **Furniture catalogue, prices and store links:** [not built yet]