//
//  DocumentsPage.swift
//  HealthEnclaveTerminal
//
//  Created by Lukas Schmierer on 15.06.20.
//
import Foundation
import GLibObject
import Gtk

#if os(macOS)
import Combine
#else
import OpenCombine
#endif

import HealthEnclaveCommon

class DocumentsPage: Box {
    private let model: DocumentsModel
    
    private let treeIter = TreeIter()
    private let store: ListStore
    
    private var documentAddedSubscription: Cancellable?
    
    init(model: DocumentsModel) {
        self.model = model
        store = ListStore(.string, .string, .string)
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
        
        let treeView = TreeView(model: store)
        
        let nameColumn = TreeViewColumn(0)
        nameColumn.title = "Document"
        nameColumn.resizable = true
        nameColumn.expand = true
        nameColumn.sortColumnID = 0
        _ = treeView.append(column: nameColumn)
        
        let createdAtColumn = TreeViewColumn(1)
        createdAtColumn.title = "Created At"
        createdAtColumn.minWidth = 200
        createdAtColumn.resizable = true
        createdAtColumn.expand = false
        createdAtColumn.sortColumnID = 1
        _ = treeView.append(column: createdAtColumn)
        
        let createdByColumn = TreeViewColumn(2)
        createdByColumn.title = "Created By"
        createdByColumn.minWidth = 200
        createdByColumn.resizable = true
        createdByColumn.expand = false
        createdByColumn.sortColumnID = 2
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
        dateFormatter.dateFormat = "yyyy-mm-dd hh:mm"
        store.append(asNextRow: treeIter,
                     Value(documentMetadata.name),
                     Value(dateFormatter.string(from: documentMetadata.createdAt.date)),
                     Value(documentMetadata.createdBy))
    }
}
