/**
* ZeroDark.cloud
* <GitHub wiki link goes here>
*
* Sample App: ZeroDarkTodo
**/

import UIKit
import ZeroDarkCloud

extension Notification.Name {
	static let UIDatabaseConnectionWillUpdateNotification = Notification.Name("UIDatabaseConnectionWillUpdateNotification")
	static let UIDatabaseConnectionDidUpdateNotification = Notification.Name("UIDatabaseConnectionDidUpdateNotification")

	static let ZDCPullStartedNotification =
		Notification.Name("ZDCPullStartedNotification")
	static let ZDCPullStoppedNotification =
		Notification.Name("ZDCPullStoppedNotification")
	static let ZDCPushStartedNotification =
		Notification.Name("ZDCPushStartedNotification")
	static let ZDCPushStoppedNotification =
		Notification.Name("ZDCPushStoppedNotification")

}

let kNotificationsKey = "notifications";

let kZDC_DatabaseName = "ZeroDarkTodo";
let kZDC_zAppID       = "com.4th-a.ZeroDarkTodo"

let Ext_View_Lists         = "List View";
let Ext_View_Tasks         = "Tasks View";
let Ext_View_Pending_Tasks = "Pending Tasks View";


class ZDCManager: NSObject, ZeroDarkCloudDelegate {
	
	var zdc: ZeroDarkCloud!
	
	private init(databaseName: String, zAppID: String) {
		super.init()

		zdc = ZeroDarkCloud(delegate: self,
		                databaseName: databaseName,
		                      zAppID: zAppID)

		do {
			let dbEncryptionKey = try zdc.databaseKeyManager.unlockUsingKeychainKey()
			let config = databaseConfig(encryptionKey: dbEncryptionKey)
			zdc.unlockOrCreateDatabase(config)			
		} catch {
			
			print("Ooops! Something went wrong: \(error)")
		}
		
		if zdc.isDatabaseUnlocked {
			self.downloadMissingOrOutdatedNodes()
			
			zdc.reachability.setReachabilityStatusChange { (status: AFNetworkReachabilityStatus) in
				
				if status == .reachableViaWiFi || status == .reachableViaWWAN {
					self.downloadMissingOrOutdatedNodes()
				}
			}
		}
	}
	
	public static var sharedInstance: ZDCManager = {
		let zdcManager = ZDCManager(databaseName: kZDC_DatabaseName, zAppID: kZDC_zAppID)
		return zdcManager
	}()
	
	/// Called from AppDelegate.
	/// Just gives us a place to setup the sharedInstance.
	///
	class func setup() {
		let _ = sharedInstance.zdc
	}
	
	/// Returns the ZeroDarkCloud instance used by the app.
	///
	class func zdc() -> ZeroDarkCloud {
		return sharedInstance.zdc
	}
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// MARK: Convenience functions
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	class func uiDatabaseConnection() -> YapDatabaseConnection {
		return sharedInstance.zdc.databaseManager!.uiDatabaseConnection
	}
	
	class func rwDatabaseConnection() -> YapDatabaseConnection {
		return sharedInstance.zdc.databaseManager!.rwDatabaseConnection
	}
	
	class func databaseManager() -> ZDCDatabaseManager {
		return sharedInstance.zdc.databaseManager!
	}
	
	class func localUserManager() -> ZDCLocalUserManager {
		return sharedInstance.zdc.localUserManager!
	}
	
	class func searchManager() -> ZDCSearchUserManager {
		return sharedInstance.zdc.searchManager!
	}
	
	class func uiTools() -> ZDCUITools {
		return sharedInstance.zdc.uiTools!
	}
	
	class func imageManager() -> ZDCImageManager {
		return sharedInstance.zdc.imageManager!
	}
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// MARK: YapDatabase Configuration
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	func databaseConfig(encryptionKey: Data) -> ZDCDatabaseConfig {
		
		let config = ZDCDatabaseConfig(encryptionKey: encryptionKey)
		
		config.serializer = databaseSerializer()
		config.deserializer = databaseDeserializer()
		
		config.extensionsRegistration = {(database: YapDatabase) in
			
			self.setupView_Lists(database)
			self.setupView_Tasks(database)
			self.setupView_PendingTasks(database)
		}
		
		return config
	}
	
	/// A 'serializer' is a block that takes an object,
	/// and turns it into raw Data so that it can be stored in the database.
	///
	/// The default serializer in YapDatabase uses NSKeyedArchiver,
	/// which means it supports any objects that support NSCoding.
	/// But we prefer to use Swift's new Codable protocol instead.
	/// So we supply our own serializer so we can use Codable instead of NSCoding.
	///
	func databaseSerializer() -> YapDatabaseSerializer {
		
		let serializer: YapDatabaseSerializer = {(collection: String, key: String, object: Any) -> Data in
			
			if let list = object as? List {
				
				let encoder = PropertyListEncoder()
				do {
					return try encoder.encode(list)
				} catch {}
			}
			if let task = object as? Task {
				
				let encoder = PropertyListEncoder()
				do {
					return try encoder.encode(task)
				} catch {}
			}
			
			return Data()
		}
		return serializer
	}
	
	/// A 'deserializer' is a block that takes raw data,
	/// and generates the original serialized object from that data.
	///
	/// As mentioned above, the default serializer/deserializer in YapDatabase supports NSCoding.
	/// But we prefer to use Swift's new Codable protocol instead.
	/// So we supply our own custom serializer & deserializer.
	///
	func databaseDeserializer() -> YapDatabaseDeserializer {
		
		let deserializer: YapDatabaseDeserializer = {(collection: String, key: String, data: Data) -> Any in
			
			if collection == kZ2DCollection_List {
				
				let decoder = PropertyListDecoder()
				do {
					return try decoder.decode(List.self, from: data)
				} catch {}
			}
			if collection == kZ2DCollection_Task {
				
				let decoder = PropertyListDecoder()
				do {
					return try decoder.decode(Task.self, from: data)
				} catch {}
			}
			
			return NSNull()
		}
		return deserializer
	}
	
	/// YapDatabase is a collection/key/value store.
	/// This sample app is storing 2 different types of objects in the database:
	///
	/// - List (in collection kZ2DCollection_List)
	/// - Task (in collection kZ2DCollection_Task)
	///
	/// In the user interface, we need to display a tableView of all the Lists.
	/// The question is, how do we sort the Lists ?
	/// There are multiple ways we could go about this.
	/// For this example we're simply going to allow the user to sort the lists manually.
	///
	func setupView_Lists(_ database: YapDatabase) {
		
		// A YapDatabaseManualView is an extension for YapDatabase.
		// It allows us to manually store a list of {collection,key} tuples.
		//
		// We're going to use it to store the order of the List items in the databsae.
		// That is, if the user drags items around to re-sort the list, we need to save that information.
		// YapDatabaseManualView is tool that's designed to do just that.
		//
		let view = YapDatabaseManualView()
		
		database.asyncRegister(view, withName: Ext_View_Lists) {(ready) in
			
			if !ready {
				print("Error registering \"%@\" !!!", Ext_View_Lists)
			}
		}
	}
	
	/// In the user interface, we need to display a tableView of all the tasks in a list.
	/// We need to sort these tasks somehow.
	/// We use a YapDatabaseView to accomplish this, as described below.
	///
	func setupView_Tasks(_ database : YapDatabase) {
		
		// YapDatabaseAutoView is a YapDatabase extension.
		// It allows us to store a list of {collection,key} tuples.
		// Furthermore, the view creates this list automatically using a grouping & sorting block.
		//
		// YapDatabase has extensive documentation for views:
		// https://github.com/yapstudios/YapDatabase/wiki/Views
		//
		// Here's the cliff notes version:
		//
		// Imagine you're storing a large collection of Book's in the databse.
		// You'd like to create a "view" of this data wherein each book is first grouped
		// according to its genre. For example, "fiction", "mystery", "travel", etc.
		// Then, within each genre, you want to sort the books by title, in alphabetical order.
		//
		// So there are 2 tasks:
		// Task 1: GROUP the books by genre
		// Task 2: SORT the books within each genre
		//
		// And this is what we're doing here.
		//
		// The grouping block allows us to group each item into the database.
		// We simply return a string, and the view will place the item into a group that matches this string.
		// From our Books example above, this means we'd return a string like "fiction".
		// If you return nil from the grouping block, then the item isn't included in the view at all.
		//
		// And the sorting block does what you think it does.
		// It sorts 2 items just like any comparison block.
		// And YapDatabaseAutoView uses it to sort all the items in a group.
		// (Just like an Array would use a similar technique to sort the items in an Array.)
		
		
		// Group all the Task's into groups, based on their List.
		//
		let grouping = YapDatabaseViewGrouping.withObjectBlock({
			(transaction, collection, key, obj) -> String? in
			
			if let task = obj as? Task {
				return task.listID
			}
			return nil
		})
		
		// Sort all the Task's in a given List.
		//
		// We want to sort the Tasks like so:
		// - If the Task is marked as completed, move it towards the bottom of the list.
		// - If the Task is NOT completed, move it towards the top of the list.
		// - Within each section, sort the Task's by creationDate.
		//
		// There are many different ways in which we could go about doing this.
		// I bet you can think of something better.
		//
		let sorting = YapDatabaseViewSorting.withObjectBlock({
			(transaction, group, collection1, key1, obj1, collection2, key2, obj2) -> ComparisonResult in
			
			let task1 = obj1 as! Task
			let task2 = obj2 as! Task
			
			if (task1.completed && !task2.completed)
			{
				return .orderedDescending
			}
			else if (!task1.completed && task2.completed)
			{
				return .orderedAscending
			}
			else
			{
				return task2.creationDate.compare(task1.creationDate)
			}
		})
		
		let versionTag =  "2019-02-04-x"; // <---------- change me if you modify grouping or sorting
		
		let options = YapDatabaseViewOptions()
		options.allowedCollections = YapWhitelistBlacklist(whitelist: Set([kZ2DCollection_Task]))

		let view =
			YapDatabaseAutoView(grouping: grouping,
			                     sorting: sorting,
			                  versionTag: versionTag,
			                     options: options)

		database.asyncRegister(view, withName: Ext_View_Tasks) {(ready) in
			
			if !ready {
				print("Error registering \"%@\" !!!", Ext_View_Tasks)
			}
			
		}
	}
	
	// In the user interface, we need a quick way to get the total count of all Task's that are not completed.
	// We need to do this on a per-list basis.
	// So we're going to create a View that will give us this info.
	//
	func setupView_PendingTasks(_ database: YapDatabase) {
		
		// Group the Task's into groups based on their List.
		// Only include Tasks that are NOT complete.
		//
		let grouping = YapDatabaseViewGrouping.withObjectBlock(
		{(transaction, collection, key, obj) -> String? in
			
			if let task = obj as? Task {
				
				if !task.completed {
					return task.listID
				}
			}
			
			return nil
		})
		
		// It doesn't matter how we sort these Tasks.
		// We're only interested in the count (per List).
		//
		let sorting = YapDatabaseViewSorting.withObjectBlock({
			(transaction, group, collection1, key1, obj1, collection2, key2, obj2) -> ComparisonResult in
			
			let task1 = obj1 as! Task
			let task2 = obj2 as! Task
			
			return task1.uuid.compare(task2.uuid)
		})
		
		let versionTag =  "2019-02-04-x"; // <---------- change me if you modify grouping or sorting
		
		let options = YapDatabaseViewOptions()
		options.allowedCollections = YapWhitelistBlacklist(whitelist: Set([kZ2DCollection_Task]))

		let view = YapDatabaseAutoView(grouping: grouping,
		                                sorting: sorting,
		                             versionTag: versionTag,
		                                options: options)

		database.asyncRegister(view, withName: Ext_View_Pending_Tasks) { (ready) in
			if(!ready)
			{
				print("Error registering \"%@\" !!!", Ext_View_Pending_Tasks)
			}
			
		}
	}
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// MARK: ZeroDarkCloudDelegate: Push (Nodes)
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	/// ZeroDark is asking us to supply the serialized data for a node.
	/// This is the data that will get uploaded to the cloud (after ZeroDark encrypts it).
	///
	func data(for node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadTransaction) -> ZDCData {
		
		// We need to figure out what object is associated with the given node.
		// We can do that by asking the framework which {collection, key} tuple is linked to the node.
		//
		// So first we get an instance of ZDCCloudTransaction.
		// Since the ZeroDarkCloud framework supports multiple localUsers,
		// we need to get the ZDCCloudTransaction for the correct localUser.
		
		let ext = zdc.cloudTransaction(transaction, forLocalUserID: node.localUserID)
		
		// Now we can ask it what tuple is linked to this node.
		// And the collection will tell us what the object type is.
		
		if let (collection, key) = ext?.linkedCollectionAndKey(forNodeID: node.uuid) {
			
			// Now we need to serialize our object for storage in the cloud.
			// Our model classes use the `cloudEncode()` function for this task.
			
			if (collection == kZ2DCollection_List)
			{
				let listID = key
				if let list = transaction.object(forKey: listID, inCollection: collection) as? List {
					
					do {
						let data = try list.cloudEncode()
						return ZDCData(data: data)
						
					} catch {
						print("Error in list.cloudEncode(): \(error)")
					}
				}
			}
			else if (collection == kZ2DCollection_Task)
			{
				let taskID = key
				if let task = transaction.object(forKey: taskID, inCollection: collection) as? Task {
					
					do {
						let data = try task.cloudEncode()
						return ZDCData(data: data)
						
					} catch {
						print("Error in task.cloudEncode(): \(error)")
					}
				}
			}
		}
		else if path.pathComponents.count == 3 {
			
			// This is for a Task's image:
			//
			//      (home)
			//       /  \
			// (listA)  (listB)
			//           /    \
			//      (task1)   (task2)
			//         |
			//       (imgA)
			//
			// path: /{listB}/{task1}/img
			//
			// We always store the image in the DiskManager.
			// And we store it with the "persistent" flag so it can't get deleted until after we've uploaded it.
			
			if let export = zdc.diskManager?.nodeData(node),
				let cryptoFile = export.cryptoFile
			{
				return ZDCData(cryptoFile: cryptoFile)
			}
		}
		
		return ZDCData()
	}
	
	/// ZeroDark is asking for an optional metadata section for this node.
	///
	/// When ZeroDark uploads our node to the cloud, it uploads it in "CloudFile format".
	/// This is an encrypted file. But if you decrypted it, and looked inside it would look like this:
	///
	/// | header | metadata(optional) | thumbnail(optional) | data |
	///
	/// In other words, the file is composed of 4 sections.
	/// And the metadata & thumbnail sections are optional.
	///
	/// We don't use metadata in this example, so we always return nil.
	///
	func metadata(for node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadTransaction) -> ZDCData? {
		
		return nil
	}
	
	/// ZeroDark is asking for an optional thumbnail for this node.
	///
	/// When ZeroDark uploads our node to the cloud, it uploads it in "CloudFile format".
	/// This is an encrypted file. But if you decrypted it, and looked inside it would look like this:
	///
	/// | header | metadata(optional) | thumbnail(optional) | data |
	///
	/// In other words, the file is composed of 4 sections.
	/// And the metadata & thumbnail sections are optional.
	///
	/// For List & Task objects, we return nil (thumbnails don't make sense in this context).
	///
	/// But for a TaskImage we do include a thumbnail in the upload.
	/// Here's why:
	///
	/// - Imagine the user attaches a picture to a task
	/// - The picture is 5 megabytes
	/// - However, the UI generally only displays a tiny thumbnail for this image
	/// - Without a thumbnail, we would be forced to download a 5 megabyte photo when
	///   all we need most of the time is a tiny little thumbnail.
	///
	///
	/// This allows
	///
	func thumbnail(for node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadTransaction) -> ZDCData? {
		
		if path.pathComponents.count == 3 {
			
			// This is for a Task's image:
			//
			//      (home)
			//       /  \
			// (listA)  (listB)
			//           /    \
			//      (task1)   (task2)
			//         |
			//       (imgA)
			//
			// path: /{listB}/{task1}/img
			//
			// When the user sets an image, we always store the image & thumbnail in the DiskManager.
			// And we store it with the "persistent" flag so it can't get deleted until after we've uploaded it.
			
			if let export = zdc.diskManager?.nodeThumbnail(node),
				let cryptoFile = export.cryptoFile
			{
				return ZDCData(cryptoFile: cryptoFile)
			}
		}
		
		return nil
	}
	
	/// ZeroDark just pushed our data to the cloud.
	/// If the node is a List of Task, we should update our cloudETag value to match the node.
	///
	func didPushNodeData(_ node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
		
		print("ZDC Delegate: didPushNodeData:at: \(path.fullPath())")
		
		// Nothing to do here for this app
	}
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// MARK: ZeroDarkCloudDelegate: Push (Messages)
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	func messageData(for user: ZDCUser, withMessageID messageID: String, transaction: YapDatabaseReadTransaction) -> ZDCData? {
		
		return nil
	}
	
	func didSendMessage(to user: ZDCUser, withMessageID messageID: String, transaction: YapDatabaseReadWriteTransaction) {
		
		// Todo...
	}
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// MARK: ZeroDarkCloudDelegate: Pull
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	/// ZeroDark has just discovered a new node in the cloud.
	/// It's notifying us so that we can react appropriately.
	///
	func didDiscoverNewNode(_ node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
		
		print("ZDC Delegate: didDiscoverNewNode:at: \(path.fullPath())")
		
		guard let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: node.localUserID) else {
			return
		}
		
		// What kind of node is this ?
		//
		// For this sample application,
		// the easiest way to answer that question is by looking at the path.
		//
		// Given our tree hierarchy:
		//
		// - All List objects have a path that looks like : /X
		// - All Task objects have a path that looks like : /X/Y
		// - All Task images have a path that looks like  : /X/Y/Z
		//
		// So we know what type of node we're downloading based on the number of path components.
		//
		switch path.pathComponents.count
		{
		case 1:
			// This is a List object.
			cloudTransaction.markNode(asNeedsDownload: node.uuid)
				
			// We can download it now.
			downloadNode(node, at: path)
			
		case 2:
			// This is a Task object.
			cloudTransaction.markNode(asNeedsDownload: node.uuid)
			
			// Download it now IFF we have the parent List already.
			if let parentNodeID = node.parentID,
			   let _/* listID */ = cloudTransaction.linkedKey(forNodeID: parentNodeID)
			{
				downloadNode(node, at: path)
			}
			
		case 3:
			// This is a Task IMAGE.
			// Don't bother downloading this right now.
			// We can download it on demand via the UI.
			// In fact, the ZDCImageManager will help us out with it.
			break;
			
		default:
			print("Unknown cloud path: \(path)")
		}
	}
	
	/// ZeroDark has just discovered a modified node in the cloud.
	/// It's notifying us so we can react appropriately.
	///
	func didDiscoverModifiedNode(_ node: ZDCNode, with change: ZDCNodeChange, at path: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
		
		print("ZDC Delegate: didDiscoverModifiedNode::at: \(path.fullPath())")
		
		guard let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: node.localUserID) else {
			return
		}
		
		// What kind of change is this ?
		// As in, what changed in the cloud ?
		
		if change == ZDCNodeChange.treesystem {
			
			// ZDCNodeChange.treesystem:
			//
			// ZeroDark noticed something about the treesystem metadata that was changed.
			// This is usually a permissions change.
			//
			// So to ensure that our UI updates appropriately, we'll touch the object in the database.
			// This will ensure the object is included in the YapDatabaseModified notification.
			
			if let (collection, key) = cloudTransaction.linkedCollectionAndKey(forNodeID: node.uuid) {
				
				transaction.touchObject(forKey: key, inCollection: collection)
			}
		}
		else {
			
			// ZDCNodeChange.data:
			//
			// ZeroDark noticed that the node's data changed.
			// That is, the content that we generate.
			//
			// i.e. a serialized List, Task or TaskImage.
			
			// What kind of node is this ?
			//
			// For this sample application,
			// the easiest way to answer that question is by looking at the path.
			//
			// Given our tree hierarchy:
			//
			// - All List objects have a path that looks like : /X
			// - All Task objects have a path that looks like : /X/Y
			// - All Task images have a path that looks like  : /X/Y/Z
			//
			// So we know what type of node we're downloading based on the number of path components.
			//
			switch path.pathComponents.count
			{
				case 1:
					// This is a List object.
					cloudTransaction.markNode(asNeedsDownload: node.uuid)
			
					// We can download it now.
					downloadNode(node, at: path)
			
				case 2:
					// This is a Task object.
					cloudTransaction.markNode(asNeedsDownload: node.uuid)
					
					// Download it IFF we have the parent List already.
					if let parentNodeID = node.parentID,
					   let _/* listID */ = cloudTransaction.linkedKey(forNodeID: parentNodeID)
					{
						downloadNode(node, at: path)
					}
				
			case 3:
					// This is a Task IMAGE.
					//
					// Don't bother downloading this right now.
					// We can download it on demand via the UI.
					// In fact, the ZDCImageManager will help us out with it.
				
					break
			
				default:
					print("Unknown cloud path: \(path)")
			}
		}
	}
	
	func didDiscoverMovedNode(_ node: ZDCNode, from oldPath: ZDCTreesystemPath, to newPath: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
		
		// We don't move nodes around in this app, so there's nothing to do.
		//
		// Note:
		// Even if we did move nodes around, it wouldn't matter in this particular app.
		// This is because our model objects (List & Task) don't store any
		// information that relates to the node's location.
	}
	
	func didDiscoverDeletedNode(_ node: ZDCNode, at path: ZDCTreesystemPath, timestamp: Date?, transaction: YapDatabaseReadWriteTransaction) {
		
		print("ZDC Delegate: didDiscoverDeletedNode:at: \(path.fullPath())")
		
		// Todo...
	}
	
	func didDiscoverConflict(_ conflict: ZDCNodeConflict, forNode node: ZDCNode, atPath path: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
		
		print("ZDC Delegate: didDiscoverConflict: \(conflict)")
		
		if conflict == .path {
			
			// Allow framework to automatically recover by renaming the node.
			return
		}
		
		if conflict == .data {
			
			// Our node's data is out-of-date.
			
			guard let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: node.localUserID) else {
				return
			}
			
			switch path.pathComponents.count
			{
				case 1:
					// This is a List object.
					//
					// We don't bother with merging List objects since they only contain a single property.
					// So the cloud version wins.
				
					cloudTransaction.skipDataUploads(forNodeID: node.uuid)
				
				case 2:
					// This is a Task object.
					//
					// We need to download the most recent version of the node, and merge the changes.
					
					cloudTransaction.markNode(asNeedsDownload: node.uuid)
					downloadNode(node, at: path)
				
				case 3:
					// This is a Task IMAGE.
					//
					// We can't merge images.
					// So the cloud version wins.
				
					cloudTransaction.skipDataUploads(forNodeID: node.uuid)
				
				default:
					
					print("Unknown cloud path: \(path)")
			}
		}
	}
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// MARK: Download Logic
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	private func downloadNode(withNodeID nodeID: String, transaction: YapDatabaseReadTransaction) {
		
		if let node = transaction.object(forKey: nodeID, inCollection: kZDCCollection_Nodes) as? ZDCNode {
			
			if let treesystemPath = zdc.nodeManager.path(for: node, transaction: transaction) {
				
				self.downloadNode(node, at: treesystemPath)
			}
		}
	}
	
	private func downloadNode(_ node: ZDCNode, at path: ZDCTreesystemPath) {
		
		print("downloadNode:at: \(path.fullPath())")
		
		let nodeID = node.uuid
		
		// What are we downloading ?
		//
		// Given our tree hierarchy:
		//
		// - All List objects have a path that looks like: /X
		// - All Task objects have a path that looks like: /X/Y
		//
		// So we know what type of node we're downloading based on the number of path components.
		
		var isListNode = false
		var isTaskNode = false
		
		switch path.pathComponents.count
		{
		case 1:
			isListNode = true
		case 2:
			isTaskNode = true
		default:
			break
		}
		
		if !isListNode && !isTaskNode {
			
			print("No clue what you're asking me to download...")
			return
		}
		
		// We can use the ZDCDownloadManager to do the downloading for us.
		//
		// And we can tell it to use background downloading on iOS !!!
		
		let options = ZDCDownloadOptions()
		options.cacheToDiskManager = false
		options.canDownloadWhileInBackground = true
		options.completionTag = String(describing: type(of: self))
		
		let queue = DispatchQueue.global()
		
		zdc.downloadManager!.downloadNodeData(node,
														  options: options,
														  completionQueue: queue)
		{ (cloudDataInfo: ZDCCloudDataInfo?, cryptoFile: ZDCCryptoFile?, error: Error?) in
			
			if let cryptoFile = cryptoFile {
				
				do {
					// The downloaded file is still encrypted.
					// That is, the file is stored in the cloud in an encrypted fashion.
					//
					// (Remember, ZeroDark.cloud is a zero-knowledge sync & messaging system.
					//  This means the ZeroDark servers cannot read any of our content.)
					//
					// So we need to decrypt the file.
					// Since this is a small file, we can just decrypt it into memory.
					//
					// Note: We're already executing in a background thread (DispatchQueue.global).
					//       So it's fine if we read from the disk in a synchronous fashion here.
					
					let cleartext = try ZDCFileConversion.decryptCryptoFile(intoMemory: cryptoFile)
					
					// Process it
					
					if isListNode {
						self.processDownloadedList(cleartext, forNodeID: nodeID, withETag: cloudDataInfo?.eTag)
					}
					else {
						self.processDownloadedTask(cleartext, forNodeID: nodeID, withETag: cloudDataInfo?.eTag)
					}
					
				} catch {
					print("Error reading cryptoFile: \(error)")
				}
				
				// File cleanup.
				// Delete the file, unless the DiskManager is managing it.
				self.zdc.diskManager?.deleteFileIfUnmanaged(cryptoFile.fileURL)
			}
		}
	}
	
	/// Use this method to download any List or Task items that are missing or outdated.
	///
	///
	private func downloadMissingOrOutdatedNodes() {
		
		guard
			let zdc = self.zdc,
			let databaseManager = zdc.databaseManager
		else {
			// Don't call this method until the database has been unlocked
			return
		}
		
		databaseManager.roDatabaseConnection.asyncRead { (transaction) in
			
			let nodeManager = zdc.nodeManager
			
			// The sample app supports multiple logged-in users.
			// So we need to enumerate each ZDCLocalUser.
			//
			// We can get this list from the LocalUserManager.
			
			let localUserIDs = zdc.localUserManager?.allLocalUserIDs(transaction) ?? []
			for localUserID in localUserIDs {
				
				// Now what we want to do is enumerate every node in the database (for this localUser).
				// The NodeManager has a method that will do this for us.
				//
				// We're going to recursively enumerate every node within the home "directory"
				// For example, if our treesystem looks like this:
				//
				//              (home)
				//              /    \
				//        (listA)    (listB)
				//       /   |   \         \
				// (task1)(task2)(task3)   (task4)
				//
				// Then the recursiveEnumerate function would give us:
				// - ~/listA
				// - ~/listA/task1
				// - ~/listA/task2
				// - ~/listA/task3
				// - ~/listB
				// - ~/listB/task4
				
				guard
					let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: localUserID),
					
					let containerNode = nodeManager.containerNode(forLocalUserID : localUserID,
																				 zAppID         : kZDC_zAppID,
																				 container      : .home,
																				 transaction    : transaction)
				else {
					continue
				}
				
				// Minor Performance Note:
				//
				// There are 2 similar recursiveEnumerate methods in NodeManager:
				// - recursiveEnumerateNodes
				// - recursiveEnumerateNodeIDs
				//
				// They're almost identical, except one gives you a `node: ZDCNode`,
				// and the other gives you a `nodeID: String`.
				// The minor difference here is because its a little more work for
				// the framework to fetch and give you the full node. (The extra step
				// is fetching the serialized node data from the database & deserializing it.)
				//
				// So if we don't always need the full node (like in this particular situation),
				// then its a little faster to enumerate the nodeIDs.
				
				nodeManager.recursiveEnumerateNodeIDs(withParentID: containerNode.uuid,
																  transaction: transaction,
																  using:
				{ (nodeID: String, path: [String], recurseInto, stop) in
					
					let needsDownload = cloudTransaction.nodeIsMarked(asNeedsDownload: nodeID)
					if needsDownload {
						self.downloadNode(withNodeID: nodeID, transaction: transaction)
					}
					
					// The `path` gives us a list of nodeID's between `home` & `noodeID`.
					//
					// In the case of a List object, this would be an empty array.
					// In the case of a Task object, this would be an array with 1 item (the listID)
					//
					// If we don't have the List object yet, then we don't need to recurse into the children.
					// That is, if we don't have the List object in the database yet,
					// then we can't download any of the List's task items yet.
					//
					if path.count == 0 {
						
						let list = cloudTransaction.linkedObject(forNodeID: nodeID) as? List
						if list == nil {
							
							// Don't bother recursing into the List.
							// We need to download & process the List first, before we can download any of the children.
							recurseInto[0] = false
						}
					}
				})
			}
		}
	}
	
	private func downloadMissingOrOutdatedTasks(forListID listID: String, localUserID: String) {
		
		guard
			let zdc = self.zdc,
			let databaseManager = zdc.databaseManager
			else {
				
				// Don't call this method until the database has been unlocked
				return
		}
		
		databaseManager.roDatabaseConnection.asyncRead { (transaction) in
			
			guard
				let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: localUserID),
				let listNode = cloudTransaction.linkedNode(forKey: listID, inCollection: kZ2DCollection_List)
				else {
					return
			}
			
			zdc.nodeManager.enumerateNodeIDs(withParentID : listNode.uuid,
														transaction  : transaction,
														using:
			{ (nodeID, stop) in
				
				let needsDownload = cloudTransaction.nodeIsMarked(asNeedsDownload: nodeID)
				if needsDownload {
					self.downloadNode(withNodeID: nodeID, transaction: transaction)
				}
			})
		}
	}
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// MARK: Processing Logic
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	/// Invoked after a List object has been downloaded from the cloud.
	///
	private func processDownloadedList(_ cleartext: Data, forNodeID nodeID: String, withETag eTag: String?) {
		
		var listID: String? = nil
		var localUserID: String? = nil
		
		let zdc = self.zdc!
		let rwConnection = zdc.databaseManager!.rwDatabaseConnection
		rwConnection.asyncReadWrite({ (transaction) in
			
			// Fetch the most recent version of the node from the database.
			// If the node no longer exists, then we don't need to worry about processing the downloaded data,
			// and we can quietly exit.
			//
			guard
				let node = transaction.object(forKey: nodeID, inCollection: kZDCCollection_Nodes) as? ZDCNode,
				let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: node.localUserID)
				else {
					return
			}
			
			cloudTransaction.unmarkNode(asNeedsDownload: nodeID, ifETagMatches: eTag)
			
			if cloudTransaction.isNodeLinked(nodeID) {
				
				// We already created the corresponding List and linked it to this node.
				return
			}
			
			do {
				// Attempt to create a List instance from the downloaded data.
				// This could fail if:
				//
				// - there's a bug in our List.cloudEncode() function
				// - there's a bug in our List.init(fromCloudData:node:) function
				//
				let list = try List(fromCloudData: cleartext, node: node)
				
				// Store the List object in the database.
				//
				// YapDatabase is a collection/key/value store.
				// So we store all List objects in the same collection: kZ2DCollection_List
				// And every list has a uuid, which we use as the key in the database.
				//
				// Wondering how the object gets serialized / deserialized ?
				// The List object supports the Swift Codable protocol.
				
				transaction.setObject(list, forKey: list.uuid, inCollection: kZ2DCollection_List)
				
				// Where does this List object go within the context of the UI.
				// For example, imagine the situation in which there are multiple lists:
				//
				// - Groceries
				// - Weekend Chores
				// - Stuff to get @ hardware store
				//
				// We're going to display these in a TableView to the user.
				// How do we order the items ?
				// Do we automatically sort them somehow ?
				// Or do we allow the user to sort them manually ?
				//
				// For our UI we've decided to let the user sort them manually.
				// This means we also want to store the order within the database.
				// And to accomplish this, we're using an extension that does most of the work for us.
				//
				// So we just need to add the {collection,key} tuple to YapDatabaseManualView.
				
				if let vt = transaction.ext(Ext_View_Lists) as? YapDatabaseManualViewTransaction {
					
					vt.addKey(list.uuid, inCollection:kZ2DCollection_List, toGroup: node.localUserID)
				}
				
				// Link the List to the Node
				
				do {
					try cloudTransaction.linkNodeID(nodeID, toKey: list.uuid, inCollection: kZ2DCollection_List)
					
				} catch {
					print("Error linking node to list: \(error)")
					
					transaction.rollback()
					return // from block
				}
				
				listID = list.uuid
				localUserID = node.localUserID
				
			} catch {
				print("Error parsing list from cloudData: \(error)")
			}
			
		}, completionQueue: DispatchQueue.global()) {
			
			// Download any missing or outdated tasks for this list
			
			if let listID = listID, let localUserID = localUserID {
				self.downloadMissingOrOutdatedTasks(forListID: listID, localUserID: localUserID)
			}
		}
	}
	
	/// Invoked after a Task object has been downloaded from the cloud.
	///
	private func processDownloadedTask(_ cleartext: Data, forNodeID nodeID: String, withETag eTag: String?) {
		
		let zdc = self.zdc!
		let rwConnection = zdc.databaseManager!.rwDatabaseConnection
		rwConnection.asyncReadWrite({ (transaction) in
			
			// Fetch the following from the database:
			// - the node for the task
			// - the parent List
			//
			// If either of these no longer exist, then we don't need to worry about
			// processing the downloaded data, and we can quietly exit.
			//
			guard
				let node = transaction.object(forKey: nodeID, inCollection: kZDCCollection_Nodes) as? ZDCNode,
				let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: node.localUserID),
				let list = cloudTransaction.linkedObject(forNodeID: node.parentID ?? "") as? List
			else {
				return
			}
			
			cloudTransaction.unmarkNode(asNeedsDownload: nodeID, ifETagMatches: eTag)
			
			var downloadedTask: Task!
			do {
				
				// Attempt to create a Task instance from the downloaded data.
				// This could fail if:
				//
				// - there's a bug in our Task.cloudEncode() function
				// - there's a bug in our Task.init(fromCloudData:node:listID:) function
				//
				downloadedTask = try Task(fromCloudData: cleartext, node: node, listID: list.uuid)
				
			} catch {
				
				print("Error parsing task from cloudData: \(error)")
				return // from block
			}
			
			if var existingTask = cloudTransaction.linkedObject(forNodeID: nodeID) as? Task {
				
				// Update an existing Task.
				
				// The `existingTask` is immutable.
				// That is, the ZDCObject.makeImmutable() function has been called.
				// This is a safety mechanism we added in this class.
				//
				// So to make changes to the object, we first need to make a copy.
				//
				existingTask = existingTask.copy() as! Task
				
				// Next, in order to perform the merge, we need the list of changes we've made on the local device.
				// We can extract this from the list of queued changes.
				//
				let pendingChangesets = cloudTransaction.pendingChangesets(forNodeID: nodeID) as? Array<Dictionary<String, Any>> ?? []
				
				do {
					
					// Now we can perform the merge !
					// The ZDCSyncable open-source project handles this for us.
					
					let _ = try existingTask.merge(cloudVersion: downloadedTask, pendingChangesets: pendingChangesets)
					
					// Store the updated Task object in the database.
					//
					// YapDatabase is a collection/key/value store.
					// We store all Task objects in the same collection: kZ2DCollection_Task
					// And every task has a uuid, which we use as the key in the database.
					//
					// Wondering how the object gets serialized / deserialized ?
					// The Task object supports the Swift Codable protocol.
					
					transaction.setObject(existingTask, forKey: existingTask.uuid, inCollection: kZ2DCollection_Task)
					
				} catch {
					
					print("Error merging changes from cloudData: \(error)")
					
					// Since merge failed, we just fallback to using the cloud version.
					// We just need to change its uuid to match.
					//
					downloadedTask = Task(copy: downloadedTask, uuid: existingTask.uuid)
					transaction.setObject(downloadedTask, forKey: downloadedTask.uuid, inCollection: kZ2DCollection_Task)
				}
			}
			else {
				
				// Store the new Task object in the database.
				//
				// YapDatabase is a collection/key/value store.
				// We store all Task objects in the same collection: kZ2DCollection_Task
				// And every task has a uuid, which we use as the key in the database.
				//
				// Wondering how the object gets serialized / deserialized ?
				// The Task object supports the Swift Codable protocol.
				
				transaction.setObject(downloadedTask, forKey: downloadedTask.uuid, inCollection: kZ2DCollection_Task)
				
				// Link the Task to the Node
				//
				do {
					try cloudTransaction.linkNodeID(nodeID, toKey: downloadedTask.uuid, inCollection: kZ2DCollection_Task)
					
				} catch {
					print("Error linking node to task: \(error)")
				}
				
				// Where does this Task object go within the context of the UI ?
				//
				// This is handled for us automatically.
				// @see self.setupView_Tasks()
			}
			
			// Adding or modifying a task indirectly modifies the List.
			// And there are various components of our UI that should update in response to this change.
			// However, those UI components are looking for changes to the List, not to Tasks.
			// So what we want to do here is tell the database that the List was modified.
			// This way, when the DatabaseModified notification gets sent out,
			// our UI will update the List properly.
			//
			// We can accomplish this using YapDatabase's `touch` functionality.
			
			transaction.touchObject(forKey: list.uuid, inCollection: kZ2DCollection_List)
		})
	}
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// MARK: Sharing Logic
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	public func modifyListPermissions(_ listID     : String,
												 localUserID  : String,
												 newUsers     : Set<String>,
												 removedUsers : Set<String>)
	{
		if (newUsers.count == 0) && (removedUsers.count == 0) {
			return
		}
		
		let zdc = self.zdc!
		let rwConnection = zdc.databaseManager!.rwDatabaseConnection
		rwConnection.asyncReadWrite({ (transaction) in
			
			guard let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: localUserID) else {
				
				return
			}
			
			if var node = cloudTransaction.linkedNode(forKey: listID, inCollection: kZ2DCollection_List) {
				
				node = node.copy() as! ZDCNode
				
				for addedUserID in newUsers {
					
					let shareItem = ZDCShareItem()
					shareItem.addPermission(ZDCSharePermission.read)
					
					node.shareList.add(shareItem, forUserID: addedUserID)
				}
				
				for removedUserID in removedUsers {
					
					node.shareList.removeShareItem(forUserID: removedUserID)
				}
				
				do {
					try cloudTransaction.modifyNode(node)
					
				} catch {
					
					print("Error modifying node: \(error)")
					return // from transaction
				}
			}
			
			// Modifying the node indirectly modifies the List.
			// And there are various components of our UI that should update in response to this change.
			// However, those UI components are looking for changes to the List, not to the node.
			// So what we want to do here is tell the database that the List was modified.
			// This way, when the DatabaseModified notification gets sent out,
			// our UI will update the List properly.
			//
			// We can accomplish this using YapDatabase's `touch` functionality.
			
			transaction.touchObject(forKey: listID, inCollection: kZ2DCollection_List)
			
			// Todo: We need to send a message to the user(s) we added.
		})
	}
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// MARK: Image Logic
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	/// Deletes the image attached to a task.
	///
	/// Here's how this works:
	///
	/// 
	public func clearImage(forTaskID taskID: String, localUserID: String) {
		
		let zdc = self.zdc!
		let rwConnection = zdc.databaseManager!.rwDatabaseConnection
		rwConnection.asyncReadWrite({ (transaction) in
			
			guard
				let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: localUserID),
				let taskNode = cloudTransaction.linkedNode(forKey: taskID, inCollection: kZ2DCollection_Task)
				else {
					return
			}
			
			let imageNode =
				zdc.nodeManager.findNode(withName    : "img",
												 parentID    : taskNode.uuid,
												 transaction : transaction)
			
			if let imageNode = imageNode {
				
				do {
					try cloudTransaction.delete(imageNode)
				} catch {
					print("Error deleting taskImageNode: \(error)")
				}
			}
			
			// Changing the image indirectly modifies the task.
			// As in, there are various UI components that display both the task & image.
			// They monitor the database for changes to the task, and automatically update the UI accordingly.
			// But they don't monitor the task's image, and so don't properly update when the image is changed.
			//
			// So we have two options:
			// 1.) update all the UI controllers to also check for image changes
			// 2.) touch the associated task when its image changes
			//
			// We're lazy, so we're going with option 2 for now.
			
			transaction.touchObject(forKey: taskID, inCollection: kZ2DCollection_Task)
		})
	}
	
	public func setImage(_ image: UIImage, forTaskID taskID: String, localUserID: String) {
		
		guard
			let imageData = image.dataWithJPEG(),
			let thumbnailData = image.withMaxSize(CGSize(width: 256, height: 256))?.dataWithPNG()
			else {
				print("Unable to convert image to JPEG !")
				return
		}
		
		let zdc = self.zdc!
		
		var existingImageNode: ZDCNode? = nil
		zdc.databaseManager?.roDatabaseConnection.read { (transaction) in
			
			if
				let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: localUserID),
				let taskNode = cloudTransaction.linkedNode(forKey: taskID, inCollection: kZ2DCollection_Task)
			{
				existingImageNode =
					zdc.nodeManager.findNode(withName    : "img",
													 parentID    : taskNode.uuid,
													 transaction : transaction)
			}
		}
		
		let imageNodeIsNew = (existingImageNode == nil)
		let imageNode = existingImageNode ?? ZDCNode(localUserID: localUserID)
		
		DispatchQueue.global().async { // Perform disk IO off the main thread
			
			do {
				
				var diskImport = ZDCDiskImport(cleartextData: imageData)
				diskImport.storePersistently = true
				diskImport.migrateToCacheAfterUpload = true
				
				try zdc.diskManager?.importNodeData(diskImport, for: imageNode)
				
				diskImport = ZDCDiskImport(cleartextData: thumbnailData)
				diskImport.storePersistently = true
				diskImport.migrateToCacheAfterUpload = true
				
				try zdc.diskManager?.importNodeThumbnail(diskImport, for: imageNode)
				
			} catch {
				print("Error storing image in DiskManager: \(error)")
				return
			}
			
			zdc.databaseManager?.rwDatabaseConnection.asyncReadWrite({ (transaction) in
				
				guard
					let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: localUserID),
					let taskNode = cloudTransaction.linkedNode(forKey: taskID, inCollection: kZ2DCollection_Task)
					else {
						return
				}
				
				if imageNodeIsNew {
					
					imageNode.parentID = taskNode.uuid
					imageNode.name = "img"
					
					do {
						try cloudTransaction.createNode(imageNode)
					}
					catch {
						print("Error creating imageNode: \(error)")
					}
					
				} else {
					
					cloudTransaction.queueDataUpload(forNodeID: imageNode.uuid, withChangeset: nil)
				}
				
				// Changing the image indirectly modifies the task.
				// As in, there are various UI components that display both the task & image.
				// They monitor the database for changes to the task, and automatically update the UI accordingly.
				// But they don't monitor the task's image, and so don't properly update when the image is changed.
				//
				// So we have two options:
				// 1.) update all the UI controllers to also check for image changes
				// 2.) touch the associated task when its image changes
				//
				// We're lazy, so we're going with option 2 for now.
				
				transaction.touchObject(forKey: taskID, inCollection: kZ2DCollection_Task)
			})
		}
	}
}
