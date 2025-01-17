//
//  LibraryViewController.swift
//  r2-testapp-swift
//
//  Created by Alexandre Camilleri on 8/24/17.
//
//  Copyright 2018 European Digital Reading Lab. All rights reserved.
//  Licensed to the Readium Foundation under one or more contributor license agreements.
//  Use of this source code is governed by a BSD-style license which is detailed in the
//  LICENSE file present in the project repository where this source code is maintained.
//

import Combine
import UIKit
import MobileCoreServices
import WebKit
import R2Shared
import R2Streamer
import R2Navigator
import Kingfisher
import ReadiumOPDS


protocol LibraryViewControllerFactory {
    func make() -> LibraryViewController
}

class LibraryViewController: UIViewController, Loggable {
    
    typealias Factory = DetailsTableViewControllerFactory
    
    var factory: Factory!
    private var books: [Book] = []
    
    weak var lastFlippedCell: PublicationCollectionViewCell?
    
    var library: LibraryService! {
        didSet {
            oldValue?.delegate = nil
            library.delegate = self
        }
    }
    
    weak var libraryDelegate: LibraryModuleDelegate?
    
    private var subscriptions = Set<AnyCancellable>()
    
    lazy var loadingIndicator = PublicationIndicator()
    private lazy var addBookButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addBook))
    
    @IBOutlet weak var collectionView: UICollectionView! {
        didSet {
            // The contentInset of collectionVIew might be changed by iOS 9/10.
            // This property has been set as false on storyboard.
            // In case it's changed by mistake somewhere, set it again here.
            self.automaticallyAdjustsScrollViewInsets = false
            
            collectionView.backgroundColor = #colorLiteral(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
            collectionView.contentInset = UIEdgeInsets(top: 15, left: 20,
                                                       bottom: 20, right: 20)
            collectionView.register(UINib(nibName: "PublicationCollectionViewCell", bundle: nil),
                                    forCellWithReuseIdentifier: "publicationCollectionViewCell")
            collectionView.delegate = self
            collectionView.dataSource = self
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        library.allBooks()
            .receive(on: DispatchQueue.main)
            .sink { completion in
                if case .failure(let error) = completion {
                    self.libraryDelegate?.presentError(error, from: self)
                }
            } receiveValue: { newBooks in
                self.books = newBooks
                self.collectionView.reloadData()
            }
            .store(in: &subscriptions)
        
        // Add long press gesture recognizer.
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        
        recognizer.minimumPressDuration = 0.5
        recognizer.delaysTouchesBegan = true
        collectionView.addGestureRecognizer(recognizer)
        collectionView.accessibilityLabel = NSLocalizedString("library_a11y_label", comment: "Accessibility label for the library collection view")
        
        self.navigationItem.rightBarButtonItem = addBookButton
        
        navigationController?.navigationBar.tintColor = #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1)
        navigationController?.navigationBar.barTintColor = #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        navigationController?.setNavigationBarHidden(false, animated: animated)
        super.viewWillAppear(animated)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        lastFlippedCell?.flipMenu()
        super.viewWillDisappear(animated)
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        collectionView.collectionViewLayout.invalidateLayout()
    }

    static let iPadLayoutNumberPerRow:[ScreenOrientation: Int] = [.portrait: 4, .landscape: 5]
    static let iPhoneLayoutNumberPerRow:[ScreenOrientation: Int] = [.portrait: 3, .landscape: 4]
    
    static let layoutNumberPerRow:[UIUserInterfaceIdiom:[ScreenOrientation: Int]] = [
        .pad : LibraryViewController.iPadLayoutNumberPerRow,
        .phone : LibraryViewController.iPhoneLayoutNumberPerRow
    ]
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        
        let idiom = { () -> UIUserInterfaceIdiom in
            let tempIdion = UIDevice.current.userInterfaceIdiom
            return (tempIdion != .pad) ? .phone:.pad // ignnore carplay and others
        } ()
        
        let layoutNumberPerRow:[UIUserInterfaceIdiom:[ScreenOrientation: Int]] = [
            .pad : LibraryViewController.iPadLayoutNumberPerRow,
            .phone : LibraryViewController.iPhoneLayoutNumberPerRow
        ]

        guard let deviceLayoutNumberPerRow = layoutNumberPerRow[idiom] else {return}
        guard let numberPerRow = deviceLayoutNumberPerRow[.current] else {return}
        
        guard let flowLayout = self.collectionView.collectionViewLayout as? UICollectionViewFlowLayout else {return}
        let contentWith = collectionView.collectionViewLayout.collectionViewContentSize.width
        
        let minimumSpacing = CGFloat(5)
        let width = (contentWith - CGFloat(numberPerRow-1) * minimumSpacing) / CGFloat(numberPerRow)
        let height = width * 1.9
        
        flowLayout.minimumLineSpacing = minimumSpacing * 2
        flowLayout.minimumInteritemSpacing = minimumSpacing
        flowLayout.itemSize = CGSize(width: width, height: height)
    }
    
    @objc func addBook() {
        let alert = UIAlertController(title: NSLocalizedString("library_add_book_title", comment: "Title for the Add book alert"), message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: NSLocalizedString("library_add_book_from_device_button", comment: "`Add a book from your device` button"), style: .default, handler: { _ in self.addBookFromDevice() }))
        alert.addAction(UIAlertAction(title: NSLocalizedString("library_add_book_from_url_button", comment: "`Add a book from a URL` button"), style: .default, handler: { _ in self.addBookFromURL() }))
      
        // LingVisSDK...
        alert.addAction(UIAlertAction(title: "Sign In", style: .default, handler: { _ in self.signIn() }))
        alert.addAction(UIAlertAction(title: "Sign Up", style: .default, handler: { _ in self.signUp() }))
        alert.addAction(UIAlertAction(title: "Sign Out", style: .default, handler: { _ in self.signOut() }))
        alert.addAction(UIAlertAction(title: "Get Settings", style: .default, handler: { _ in self.getSettings() }))
        alert.addAction(UIAlertAction(title: "Update Settings", style: .default, handler: { _ in self.updateSettings() }))
        // ...LingVisSDK
      
        alert.addAction(UIAlertAction(title: NSLocalizedString("cancel_button", comment: "Cancel adding a book from a URL"), style: .cancel))
        alert.popoverPresentationController?.barButtonItem = addBookButton
        present(alert, animated: true)
    }
    
    // LingVisSDK...
    private func signIn() {
      signInInt(newAccount: false)
    }

    private func signUp() {
      signInInt(newAccount: true)
    }
    
    private func signOut() {
      LingVisSDK.signOut(completion: { result in
        switch result {
          case .success:
            toast("Signed out", on: self.view, duration: 5)
          case .failure(let error):
            toast("ERROR: " + error.description, on: self.view, duration: 5)
        }
      })
    }
  
    private func signInInt(newAccount: Bool) {
      let title = newAccount ? "Sign Up" : "Sign In";
      let message = newAccount ? "create a new account" : "use an existing account";
      let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        func doIt(_ action: UIAlertAction) {
            guard let email = alert.textFields?[0].text, let password = alert.textFields?[1].text else
            {
                return
            }
            // Client keys encrypt client id, client secret, and user id (email). See the 'Security' section in the documentation for instructions how to create them.
            // You only need client keys if you are using a secure client id. If you choose to use a client id that is not secure, clientKey argument and didExpire event are ignored.
            // Client key must be generated on your server. It should never be generated on the client because its generation includes client secret that should NEVER be exposed.
            // This particular key has no expiration date, for demo purposes. Don't do it in production, always specify a short expiration period. Recommended value for expireIn: 10 minutes.
            // This particular key was created for the demo user "web-sample.bogus@sprakkraft.com". Trying the secure client id in this sample, use that user email. Since any key is generated tied to a specific user, it will not work for other users.
            let key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJjbGllbnRJZCI6IjQwYzc2Y2RhLWJkOWItNGI2Yy1hYWZkLTEzN2IxODdiZWRmNCIsImVtYWlsIjoid2ViLXNhbXBsZS5ib2d1c0BzcHJha2tyYWZ0LmNvbSIsImlhdCI6MTY1NDQ0NzAxMn0.0kFpW3-HMRgVYJ-QxQ8wZQ8WderpKGjBHmah2ynmNRs"
            // key and didExpire are used only if you use a secure client id. Otherwise, they are ignored.
            func onExpired(refresh: (String) -> Void) {
                refresh(key)
            }
            LingVisSDK.didExpire = onExpired
            LingVisSDK.signIn(email: email, password: password, newAccount: newAccount, autogenerated: false, completion: { result in
                switch result {
                  case .success:
                    toast("Signed in as " + email, on: self.view, duration: 5)
                  case .failure(let error):
                    toast("ERROR: " + error.description, on: self.view, duration: 5)
                }
            }, clientKey: key)
        }
        
        alert.addTextField { textField in
            textField.placeholder = "Email"
        }
        alert.addTextField { textField in
            textField.placeholder = "Password"
        }
        alert.addAction(UIAlertAction(title: title, style: .default, handler: doIt))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true, completion: nil)
    }
    
    private func showSettings(res: String) {
      let parts = res.components(separatedBy: ",")
      let msg = "Learning language: \(parts[0])\nYour language: \(parts[1])\nYour level: \(parts[2])\nemail: \(parts[3])"
      let alert = UIAlertController(title: "Settings", message: msg, preferredStyle: UIAlertController.Style.alert)
      alert.addAction(UIAlertAction(title: "OK", style: UIAlertAction.Style.default, handler: nil))
      self.present(alert, animated: true, completion: nil)
    }
    
    private func getSettings() {
      LingVisSDK.getSettings(completion: { result in
        switch result {
          case .success(let res):
            self.showSettings(res: res)
          case .failure(let error):
            toast("ERROR: " + error.description, on: self.view, duration: 5)
        }
      })
    }
    
    private func updateSettings() {
      let alert = UIAlertController(title: "Update Settings", message: "Change any of the settings below, leave empty those you don't want to change", preferredStyle: .alert)
        func doIt(_ action: UIAlertAction) {
            guard let l2 = alert.textFields?[0].text,
                  let l1 = alert.textFields?[1].text,
                  let level = alert.textFields?[2].text
            else { return }
            LingVisSDK.updateSettings(l2: l2, l1: l1, level: level, completion: { result in
                switch result {
                  case .success(let res):
                    self.showSettings(res: res)
                  case .failure(let error):
                    toast("ERROR: " + error.description, on: self.view, duration: 5)
                }
            })
        }
        
        alert.addTextField { textField in
            textField.placeholder = "Language you learn"
        }
        alert.addTextField { textField in
            textField.placeholder = "Language to translate to"
        }
        alert.addTextField { textField in
            textField.placeholder = "Your level from 1 to 6 (A1-C2)"
        }
        alert.addAction(UIAlertAction(title: "Update", style: .default, handler: doIt))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true, completion: nil)
    }
    // ...LingVisSDK

    private func addBookFromDevice() {
        var utis = DocumentTypes.main.supportedUTIs
        utis.append(String(kUTTypeText))
        let documentPicker = UIDocumentPickerViewController(documentTypes: utis, in: .import)
        documentPicker.delegate = self
        present(documentPicker, animated: true, completion: nil)
    }
    
    private func addBookFromURL(url: String? = nil, message: String? = nil) {
        let alert = UIAlertController(
            title: NSLocalizedString("library_add_book_from_url_title", comment: "Title for the `Add book from URL` alert"),
            message: message,
            preferredStyle: .alert
        )
        
        func retry(message: String? = nil) {
            addBookFromURL(url: alert.textFields?[0].text, message: message)
        }
        
        func add(_ action: UIAlertAction) {
            let optionalURLString = alert.textFields?[0].text
            guard let urlString = optionalURLString,
                let url = URL(string: urlString) else
            {
                retry(message: NSLocalizedString("library_add_book_from_url_failure_message", comment: "Error message when trying to add a book from a URL"))
                return
            }
            
            func tryAdd(from url: URL) {
                library.importPublication(from: url, sender: self)
                    .receive(on: DispatchQueue.main)
                    .sink { completion in
                        if case .failure(let error) = completion {
                            retry(message: error.localizedDescription)
                        }
                    } receiveValue: { _ in }
                    .store(in: &subscriptions)
            }

            let hideActivity = toastActivity(on: view)
            OPDSParser.parseURL(url: url) { data, _ in
                DispatchQueue.main.async {
                    hideActivity()

                    if let downloadLink = data?.publication?.downloadLinks.first, let downloadURL = URL(string: downloadLink.href) {
                        tryAdd(from: downloadURL)
                    } else {
                        tryAdd(from: url)
                    }
                }
            }
        }
        
        alert.addTextField { textField in
            textField.placeholder = NSLocalizedString("library_add_book_from_url_placeholder", comment: "Placeholder for the URL field in the `Add book from URL` alert")
            textField.text = url
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("add_button", comment: "Add a book from a URL button"), style: .default, handler: add))
        alert.addAction(UIAlertAction(title: NSLocalizedString("cancel_button", comment: "Cancel adding a boom from a URL button"), style: .cancel))
        present(alert, animated: true, completion: nil)
    }
    
}

extension LibraryViewController {
    @objc func handleLongPress(gestureRecognizer: UILongPressGestureRecognizer) {
        if (gestureRecognizer.state != UIGestureRecognizer.State.began) {
            return
        }
        
        let location = gestureRecognizer.location(in: collectionView)
        if let indexPath = collectionView.indexPathForItem(at: location) {
            let cell = collectionView.cellForItem(at: indexPath) as! PublicationCollectionViewCell
            cell.flipMenu()
        }
    }
}

// MARK: - UIDocumentPickerDelegate.
extension LibraryViewController: UIDocumentPickerDelegate {

    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard controller.documentPickerMode == .import else {
            return
        }
        importFiles(at: urls)
    }
    
    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        importFiles(at: [url])
    }
    
    private func importFiles(at urls: [URL]) {
        library.importPublications(from: urls, sender: self)
            .receive(on: DispatchQueue.main)
            .sink { completion in
                if case .failure(let error) = completion {
                    self.libraryDelegate?.presentError(error, from: self)
                }
            } receiveValue: { _ in }
            .store(in: &subscriptions)
    }
    
}

// MARK: - CollectionView Datasource.
extension LibraryViewController: UICollectionViewDelegateFlowLayout, UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if books.isEmpty {
            let noPublicationLabel = UILabel(frame: collectionView.frame)
            noPublicationLabel.text = NSLocalizedString("library_empty_message", comment: "Hint message when the library is empty")
            noPublicationLabel.textColor = UIColor.gray
            noPublicationLabel.textAlignment = .center
            collectionView.backgroundView = noPublicationLabel
        } else {
            collectionView.backgroundView = nil
        }
        
        return books.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "publicationCollectionViewCell", for: indexPath) as! PublicationCollectionViewCell
        cell.coverImageView.image = nil
        cell.progress = 0
        
        cell.isAccessibilityElement = true
        cell.accessibilityHint = NSLocalizedString("library_publication_a11y_hint", comment: "Accessibility hint for the publication collection cell")
        
        let book = books[indexPath.item]
        cell.delegate = self
        cell.accessibilityLabel = book.title
        cell.titleLabel.text = book.title
        cell.authorLabel.text = book.authors
        
        // Load image and then apply the shadow.
        if
            let coverURL = book.cover,
            let data = try? Data(contentsOf: coverURL),
            let cover = UIImage(data: data)
        {
            cell.coverImageView.image = cover
        } else {
            
            let flowLayout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout
            let description = book.title
            let textView = defaultCover(layout: flowLayout, description:description)
            cell.coverImageView.image = UIImage.imageWithTextView(textView: textView)
        }
        
        return cell
    }
    
    internal func defaultCover(layout: UICollectionViewFlowLayout?, description: String) -> UITextView {
        let width = layout?.itemSize.width ?? 0
        let height = layout?.itemSize.height ?? 0
        let titleTextView = UITextView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        
        titleTextView.layer.borderWidth = 5.0
        titleTextView.layer.borderColor = #colorLiteral(red: 0.08269290555, green: 0.2627741129, blue: 0.3623990017, alpha: 1).cgColor
        titleTextView.backgroundColor = #colorLiteral(red: 0.05882352963, green: 0.180392161, blue: 0.2470588237, alpha: 1)
        titleTextView.textColor = #colorLiteral(red: 0.8639426257, green: 0.8639426257, blue: 0.8639426257, alpha: 1)
        titleTextView.text = description.appending("\n_________") //Dirty styling.
        
        return titleTextView
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let libraryDelegate = libraryDelegate else {
            return
        }
        guard let cell = collectionView.cellForItem(at: indexPath) else {return}
        cell.contentView.addSubview(self.loadingIndicator)
        collectionView.isUserInteractionEnabled = false
        
        func done() {
            self.loadingIndicator.removeFromSuperview()
            collectionView.isUserInteractionEnabled = true
        }
        
        let book = books[indexPath.item]
        library.openBook(book, forPresentation: true, sender: self)
            .receive(on: DispatchQueue.main)
            .sink { completion in
                if case .failure(let error) = completion {
                    self.libraryDelegate?.presentError(error, from: self)
                }
                done()
            } receiveValue: { pub in
                libraryDelegate.libraryDidSelectPublication(pub, book: book, completion: done)
            }
            .store(in: &subscriptions)
    }
}

extension LibraryViewController: PublicationCollectionViewCellDelegate {
    
    func removePublicationFromLibrary(forCellAt indexPath: IndexPath) {
        let book = self.books[indexPath.item]
        
        let removePublicationAlert = UIAlertController(
            title: NSLocalizedString("library_delete_alert_title", comment: "Title of the publication remove confirmation alert"),
            message: NSLocalizedString("library_delete_alert_message", comment: "Message of the publication remove confirmation alert"),
            preferredStyle: .alert
        )
        let removeAction = UIAlertAction(title: NSLocalizedString("remove_button", comment: "Button to confirm the deletion of a publication"), style: .destructive, handler: { alert in
            self.library.remove(book)
                .sink { completion in
                    if case .failure(let error) = completion {
                        self.libraryDelegate?.presentError(error, from: self)
                    }
                } receiveValue: {}
                .store(in: &self.subscriptions)
        })
        let cancelAction = UIAlertAction(title: NSLocalizedString("cancel_button", comment: "Button to cancel the deletion of a publication"), style: .cancel)
        
        removePublicationAlert.addAction(removeAction)
        removePublicationAlert.addAction(cancelAction)
        present(removePublicationAlert, animated: true, completion: nil)
    }
    
    func displayInformation(forCellAt indexPath: IndexPath) {
        let book = books[indexPath.row]
        
        library.openBook(book, forPresentation: true, sender: self)
            .receive(on: DispatchQueue.main)
            .sink { completion in
                if case .failure(let error) = completion {
                    self.libraryDelegate?.presentError(error, from: self)
                }
            } receiveValue: { pub in
                let detailsViewController = self.factory.make(publication: pub)
                detailsViewController.modalPresentationStyle = .popover
                self.navigationController?.pushViewController(detailsViewController, animated: true)
            }
            .store(in: &subscriptions)
    }
    
    // Used to reset ui of the last flipped cell, we must not have two cells
    // flipped at the same time
    func cellFlipped(_ cell: PublicationCollectionViewCell) {
        lastFlippedCell?.flipMenu()
        lastFlippedCell = cell
    }
}

extension LibraryViewController: LibraryServiceDelegate {
    
    func confirmImportingDuplicatePublication(withTitle title: String) -> AnyPublisher<Bool, Never> {
        Future(on: .main) { promise in
            let confirmAction = UIAlertAction(title: NSLocalizedString("add_button", comment: "Confirmation button to import a duplicated publication"), style: .default) { _ in
                promise(.success(true))
            }
            
            let cancelAction = UIAlertAction(title: NSLocalizedString("cancel_button", comment: "Cancel the confirmation alert"), style: .cancel) { _ in
                promise(.success(false))
            }
    
            let alert = UIAlertController(
                title: NSLocalizedString("library_duplicate_alert_title", comment: "Title of the import confirmation alert when the publication already exists in the library"),
                message: NSLocalizedString("library_duplicate_alert_message", comment: "Message of the import confirmation alert when the publication already exists in the library"),
                preferredStyle: .alert
            )
            alert.addAction(confirmAction)
            alert.addAction(cancelAction)
            
            self.present(alert, animated: true)
        }.eraseToAnyPublisher()
    }
    
}

class PublicationIndicator: UIView  {
    
    lazy var indicator: UIActivityIndicatorView =  {
        
        let result = UIActivityIndicatorView(style: .large)
        result.translatesAutoresizingMaskIntoConstraints = false
        self.backgroundColor = UIColor(white: 0.3, alpha: 0.7)
        self.addSubview(result)
        
        let horizontalConstraint = NSLayoutConstraint(item: result, attribute: .centerX, relatedBy: .equal, toItem: self, attribute: .centerX, multiplier: 1.0, constant: 0.0)
        let verticalConstraint = NSLayoutConstraint(item: result, attribute: .centerY, relatedBy: .equal, toItem: self, attribute: .centerY, multiplier: 1.0, constant: 0.0)
        self.addConstraints([horizontalConstraint, verticalConstraint])
        
        return result
    }()
    
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        
        guard let superView = self.superview else {return}
        self.translatesAutoresizingMaskIntoConstraints = false
        
        let horizontalConstraint = NSLayoutConstraint(item: self, attribute: .centerX, relatedBy: .equal, toItem: superView, attribute: .centerX, multiplier: 1.0, constant: 0.0)
        let verticalConstraint = NSLayoutConstraint(item: self, attribute: .centerY, relatedBy: .equal, toItem: superView, attribute: .centerY, multiplier: 1.0, constant: 0.0)
        let widthConstraint = NSLayoutConstraint(item: self, attribute: .width, relatedBy: .equal, toItem: superView, attribute: .width, multiplier: 1.0, constant: 0.0)
        let heightConstraint = NSLayoutConstraint(item: self, attribute: .height, relatedBy: .equal, toItem: superView, attribute: .height, multiplier: 1.0, constant: 0.0)
        
        superView.addConstraints([horizontalConstraint, verticalConstraint, widthConstraint, heightConstraint])
        
        self.indicator.startAnimating()
    }
    
    override func removeFromSuperview() {
        self.indicator.stopAnimating()
        super.removeFromSuperview()
    }
}

