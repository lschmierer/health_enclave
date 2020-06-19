//
//  DocumentsPage.swift
//  HealthEnclaveTerminal
//
//  Created by Lukas Schmierer on 15.06.20.
//
import Gtk
import CGtk

class DocumentsPage: Box {
    private let model: DeviceDocumentsModel
    
    init(model: DeviceDocumentsModel) {
        self.model = model
        super.init(orientation: .vertical, spacing: 0)
        
        let toolbar = Toolbar()
        toolbar.style = .icons
        
        let addIcon = Image(iconName: "list-add", size: .small_toolbar)
        let addButton = ToolButton(icon_widget: addIcon, label: "Add")
        addButton.tooltipText = "Add Document"
        addButton.connect(ToolButtonSignalName.clicked, handler: addDocument)
        toolbar.add(addButton)
        
        let store = ListStore(.string, .string, .string)
        let i = TreeIter()
        store.append(asNextRow: i, "document", "15.4.2020 7:32", "Dr. X")
        store.append(asNextRow: i, "document2", "13.4.2020 18:17", "Dr. X")
        
        let treeView = TreeView(model: store)
        
        let nameColumn = TreeViewColumn(0)
        nameColumn.title = "Document"
        nameColumn.resizable = true
        nameColumn.expand = true
        treeView.append(column: nameColumn)
        
        let createdAtColumn = TreeViewColumn(1)
        createdAtColumn.title = "Created At"
        createdAtColumn.minWidth = 200
        createdAtColumn.resizable = true
        createdAtColumn.expand = false
        treeView.append(column: createdAtColumn)
        
        let createdByColumn = TreeViewColumn(2)
        createdByColumn.title = "Created By"
        createdByColumn.minWidth = 200
        createdByColumn.resizable = true
        createdByColumn.expand = false
        treeView.append(column: createdByColumn)
        
        add(widgets: [toolbar, treeView])
        showAll()
    }
    
    func addDocument() {
        let dialog = FileChooserDialog(title: "Add Document",
                                       action: .open,
                                       firstText: "_Cancel",
                                       firstResponseType: .cancel,
                                       secondText: "_Open",
                                       secondResponseType: .accept)
        if (dialog.run() == ResponseType.accept.rawValue)
        {
            debugPrint(dialog.filename)
        }
        dialog.destroy()
    }
}
