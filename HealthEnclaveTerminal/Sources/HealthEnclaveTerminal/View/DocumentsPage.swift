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

typealias RowActivatedSignalHandler = (TreeViewRef, TreePathRef, TreeViewColumnRef) -> Void
typealias RowActivatedSignalHandlerrClosureHolder = Closure3Holder<TreeViewRef, TreePathRef, TreeViewColumnRef, Void>

extension TreeViewProtocol {
    private func _connect(signal name: UnsafePointer<gchar>, flags: ConnectFlags, data: RowActivatedSignalHandlerrClosureHolder, handler: @convention(c) @escaping (gpointer, gpointer, gpointer, gpointer) -> ()) -> Int {
        let opaqueHolder = Unmanaged.passRetained(data).toOpaque()
        let callback = unsafeBitCast(handler, to: Callback.self)
        let rv = signalConnectData(detailedSignal: name, cHandler: callback, data: opaqueHolder, destroyData: {
            if let swift = $0 {
                let holder = Unmanaged<RowActivatedSignalHandlerrClosureHolder>.fromOpaque(swift)
                holder.release()
            }
            let _ = $1
        }, connectFlags: flags)
        return rv
    }
    
    func connectRowActivated(name: UnsafePointer<gchar>, flags f: ConnectFlags = ConnectFlags(0), handler: @escaping RowActivatedSignalHandler) -> Int {
        let rv = _connect(signal: name, flags: f, data: Closure3Holder(handler)) {
            let holder = Unmanaged<RowActivatedSignalHandlerrClosureHolder>.fromOpaque($3).takeUnretainedValue()
            holder.call(TreeViewRef(raw: $0), TreePathRef(raw: $1), TreeViewColumnRef(raw: $2))
        }
        return rv
    }
}

typealias OpenUrlCallback = (URL) -> Void

class DocumentsPage: Box {
    private let model: DocumentsModel
    
    private let treeView: TreeView
    private let treeIter = TreeIter()
    private let store: ListStore
    
    private let openUrlCallback: OpenUrlCallback
    
    private var documentAddedSubscription: Cancellable?
    private var openDocumentSubscription: Cancellable?
    
    init(model: DocumentsModel, openUrl openUrlCallback: @escaping OpenUrlCallback) {
        self.model = model
        store = ListStore(.string, .string, .string, .string)
        store.set(sortColumnID: 2, order: .descending)
        treeView = TreeView(model: store)
        self.openUrlCallback = openUrlCallback
        super.init(orientation: .vertical, spacing: 0)
        
        let toolbar = Toolbar()
        toolbar.style = .icons
        
        let addIcon = Image(iconName: "list-add", size: .smallToolbar)
        let addButton = ToolButton(icon_widget: addIcon, label: "Add")
        addButton.tooltipText = "Add Document"
        addButton.connect(ToolButtonSignalName.clicked, handler: addNewDocument)
        toolbar.add(addButton)
        
        for documentMetadata in model.documentsMetadata {
            addDocumentToList(documentMetadata)
        }
        
        documentAddedSubscription = model.documentAddedSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] documentMetadata in
                self?.addDocumentToList(documentMetadata)
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
    
    private func documentSelected(_ path: TreePathProtocol) {
        _ = store.get(iter: treeIter, path: path)
        let uuid = Value()
        store.getValue(iter: treeIter, column: 0, value: uuid)
        openDocument(HealthEnclave_DocumentIdentifier.with {
            $0.uuid = uuid.string
        })
    }
    
    private func openDocument(_ documentIdentifier: HealthEnclave_DocumentIdentifier) {
        openDocumentSubscription = try! model.retrieveDocument(documentIdentifier)
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] documentUrl in
                self?.openUrlCallback(documentUrl)
            })
    }
}
