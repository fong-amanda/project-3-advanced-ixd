## Get the beta

**On an iPhone:** open the TestFlight link, install Apple's free **TestFlight** app when asked, then tap **Install** next to Shared Space: Sort a Room.

> TestFlight link: *(added once Apple approves the beta)*

- Needs an iPhone with **iOS 18** or later. There's no Android version.
- Room scanning (LiDAR) needs an iPhone **Pro** (12 Pro or later). Everything else, including AR, works on any iPhone with iOS 18.
- To sort with someone: create a room, open its **People** tab and send them the 5-character code. They tap **I'm invited** and enter it.

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

## Sharing between two phones (Supabase)

Without keys the app works on one phone only ("Sharing is off"). To let two people share a room:

1. **Create a project** at [supabase.com](https://supabase.com) (the free plan is enough). Save the database password in a password manager; the app never needs it.
2. **Turn on anonymous sign-ins:** Authentication › Sign In / Providers › **Allow anonymous sign-ins** › Save. Nobody needs an email or password; each phone gets its own anonymous account.
3. **Set up the database:** SQL Editor › New query (snippet) › paste all of [`supabase/schema.sql`](supabase/schema.sql) › **Run**. It warns about "destructive operations" because it replaces its own privacy rules; that's expected. It creates the tables, the privacy rules, the private `rooms` storage bucket and live updates. Run it again after pulling a newer version; it keeps your data.
4. **Check** Storage › `rooms` is **not** public, and Database › Publications › `supabase_realtime` has `rooms`, `items`, `designs` and `design_placements` on.
5. **Add your keys:** create `ios/SharedSpace/Resources/Supabase.local.plist` (copy `Supabase.plist` next to it) with your **Project URL** and the **Publishable key** (`sb_publishable_…`, from Project Settings › API Keys). Git ignores this file and a build step copies it into the app. Never use a **secret** / `service_role` key; the app refuses one.

Everyone who installs the app must use a build with the same keys. To invite someone, the host opens the room's **People** tab and sends the five-character room code; the other person taps **I'm invited** and enters it.

### What's stored, and who can see it

| Where | What | Who can see it |
|---|---|---|
| Supabase database | Each room (name, size, outline, room code), its things (names, sizes, positions, owners, decisions, suggestions, notes, "asked" questions), plan versions and placed pieces, and the two members' first names | Only the room's two members. Row Level Security checks membership on every read and write, so the app's public key alone can't read anything. |
| Supabase storage (private bucket) | Room photos, stripped of location and camera details before upload | Only the room's members, signed in. There are no public links. |
| This iPhone only | Everything above (so it works offline), the LiDAR scan, the 3D model, the AR map of the room, item photos | Only this phone. None of these are uploaded. The live AR camera view is never saved. |

- **The room code** is the key: anyone who has it can see the room's name, what it's becoming, and the host's and guest's first names (the join screen shows these) before joining. Share it only with the person you mean to invite.
- **Joining** with the code adds you to that room only, as its guest. A room has one guest; once someone has joined, the code is refused for anyone else until they leave.
- **Leave room** removes only the guest's membership; the host's room stays.
- **Delete room** (host only) removes the room's photos from storage and the room from the database, which deletes all its things, decisions, plans and memberships with it, for both people.
- **Offline:** changes save on the phone and upload when it's back online ("Changes will sync when you're back online").

## What's faked (needs Dan and Meg's approval)
| Feature | What's faked | Why |
|---|---|---|
| **Furniture catalogue** (Redesign › Add furniture) | 28 sample pieces with realistic sizes, but made-up prices and no store links or real products | Licensing real retailer catalogues and prices is out of scope for a class project. The sizes are what the fit checks and AR use, and those are realistic. |
| **3D furniture in AR** (Redesign › View in your room) | Pieces show as true-size coloured boxes with their name, not 3D models | We don't have licensed 3D models. The AR itself is real: true-size placement, LiDAR occlusion, lining up with the plan, and saving moves back to it. A piece's model loads automatically once a `<catalogue id>.usdz` file is added. |

Not faked, but limited:
- **Room scans, the 3D room model, AR room maps and item photos** stay on the phone that made them and aren't shared. Room photos, the room's outline and everything about the items do sync.
- **Two people per room** (a host and one guest).
- **Sign-in is anonymous**, so deleting the app can lose access to your rooms.

## Change log
1. People said sort vs repurpose feel like two apps; testers wanted the Sort tab only when the room has things in it.
-  The user can now determine if they only want the room for sorting, planning, or both. 

2. People said to show the sorting and planning state on the Home room card
-  Room cards now show sorting and planning tags with their status

3. Actually implement Apple's RoomPlan scanning
-  Detected furniture actually becomes added items now, before it wasn't fully working

4. People said suggestions should automatically update after a photo is added
-  AI photo detection now suggests items from the photo and the user has to confirm each one rather than it being added automatically.

5. People said to make scanning more obvious
-  The photo step now has a pop up that explains AI detection with how it works. 

6. Ethical Audit: Photo step offers camera, upload or example with no text about storage or sharing
-  Green notice above the choice: who can see the photo, what to leave out, how to delete

7. Ethical Audit: There is no delete option, so a room and its photo stays forever
-  Host sees Delete room and photos. A confirmation sheet removes the room, photo, decision, and code. Tested: the home screen shows 0 rooms afterwards

8. Ethical Audit: Pin border is green, blue or orange; screen reader says only the item name
-  Pin label shows the name and status now; so screen reader will read that too

9. Ethical Audit: 9 distinct text color pairs below 4.5:1(ex. gray size text on green background), most controls under 44 px, animation ran with reduce motion 
-  All screens pass AA in light and dark mode except disabled buttons; controls are at least 44px except the numbered photo pins, which keep a small look with a 44px tap area; reduce motion stops CSS animation and the 3D camera movement