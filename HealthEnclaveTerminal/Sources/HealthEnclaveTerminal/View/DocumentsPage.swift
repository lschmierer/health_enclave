//
//  DocumentsPage.swift
//  HealthEnclaveTerminal
//
//  Created by Lukas Schmierer on 15.06.20.
//
import Foundation
import GLibObject
import Gtk
import CGtk

#if os(macOS)
import Combine
#else
import OpenCombine
#endif

import HealthEnclaveCommon

typealias OpenUrlCallback = (URL) -> Void

class DocumentsPage: Box {
    private let model: DocumentsModel
    
    private let treeView: TreeView
    private let treeIter = TreeIter()
    private let store: ListStore
    
    private let spinner: Spinner
    
    private let openUrlCallback: OpenUrlCallback
    
    private var documentAddedSubscription: Cancellable?
    private var openDocumentSubscription: Cancellable?
    
    init(model: DocumentsModel, openUrl openUrlCallback: @escaping OpenUrlCallback) {
        self.model = model
        store = ListStore(.string, .string, .string, .string)
        store.set(sortColumnID: 2, order: .descending)
        treeView = TreeView(model: store)
        spinner = Spinner()
        self.openUrlCallback = openUrlCallback
        super.init(orientation: .vertical, spacing: 0)
        
        let toolbar = Toolbar()
        toolbar.style = .icons
        
        let addIcon = Image(iconName: "list-add", size: .smallToolbar)
        let addButton = ToolButton(icon_widget: addIcon, label: "Add")
        addButton.tooltipText = "Add Document"
        addButton.connect(ToolButtonSignalName.clicked, handler: addNewDocument)
        toolbar.add(addButton)
        
        let separator = SeparatorToolItem()
        separator.draw = false
        toolbar.add(separator)
        toolbar.childSetProperty(child: separator, propertyName: "expand", value: Value(true))
        
        let spinnerItem = ToolItem()
        spinnerItem.marginEnd = 10
        spinnerItem.add(widget: spinner)
        toolbar.add(spinnerItem)
        
        for documentMetadata in model.documentsMetadata {
            addDocumentToList(documentMetadata)
        }
        
        documentAddedSubscription = model.documentAddedSubject
            .sink { [weak self] documentMetadata in
                guard let self = self else { return }
                
                _ = threadsAddIdle {
                    self.addDocumentToList(documentMetadata)
                    return false
                }
        }
        
        _ = treeView.onRowActivated { _, path, _ in
            self.documentSelected(path)
        }
        
        let nameColumn = TreeViewColumn(1)
        nameColumn.title = "Document"
        nameColumn.resizable = true
        nameColumn.expand = true
        nameColumn.sortColumnID = 1
        _ = treeView.append(column: nameColumn)
        
        let createdAtColumn = TreeViewColumn(2)
        createdAtColumn.title = "Created At"
        createdAtColumn.minWidth = 200
        createdAtColumn.resizable = true
        createdAtColumn.expand = false
        createdAtColumn.sortColumnID = 2
        _ = treeView.append(column: createdAtColumn)
        
        let createdByColumn = TreeViewColumn(3)
        createdByColumn.title = "Created By"
        createdByColumn.minWidth = 200
        createdByColumn.resizable = true
        createdByColumn.expand = false
        createdByColumn.sortColumnID = 3
        _ = treeView.append(column: createdByColumn)
        
        add(widgets: [toolbar, treeView])
        showAll()
    }
    
    private func addNewDocument() {
        let dialog = FileChooserDialog(title: "Add Document",
                                       action: .open,
                                       firstText: "_Cancel",
                                       firstResponseType: .cancel,
                                       secondText: "_Open",
                                       secondResponseType: .accept)
        if (dialog.run() == ResponseType.accept.rawValue)
        {
            try! model.addDocumentToDevice(file: URL(fileURLWithPath: dialog.filename))
        }
        dialog.destroy()
    }
    
    private func addDocumentToList(_ documentMetadata: HealthEnclave_DocumentMetadata) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        store.append(asNextRow: treeIter,
                     Value(documentMetadata.id.uuid),
                     Value(documentMetadata.name),
                     Value(dateFormatter.string(from: documentMetadata.createdAt.date)),
                     Value(documentMetadata.createdBy))
    }
    
    private func documentSelected(_ path: TreePathRef) {
        _ = store.get(iter: treeIter, path: path)
        let uuid = Value()
        store.getValue(iter: treeIter, column: 0, value: uuid)
        openDocument(HealthEnclave_DocumentIdentifier.with {
            $0.uuid = uuid.string
        })
    }
    
    private func openDocument(_ documentIdentifier: HealthEnclave_DocumentIdentifier) {
        spinner.start()
        openDocumentSubscription = try! model.retrieveDocument(documentIdentifier)
            .sink(receiveCompletion: { [weak self] completion in
                guard let self = self else { return }
                
                _ = threadsAddIdle {
                    self.spinner.stop()
                    if case let .failure(error) = completion,
                        case .noDocumentPermission = error {
                        let dialog = MessageDialog(flags: [], type: .error, buttons: .ok, markup: "No Permission", secondaryMarkup: "Patient did not give permission to access this document.")
                        dialog.set(position: .center)
                        _ = dialog.run()
                        dialog.destroy()
                    }
                    return false
                }
                }, receiveValue: { [weak self] documentUrl in
                    guard let self = self else { return }
                    
                    _ = threadsAddIdle {
                        self.openUrlCallback(documentUrl)
                        return false
                    }
            })
    }
}
