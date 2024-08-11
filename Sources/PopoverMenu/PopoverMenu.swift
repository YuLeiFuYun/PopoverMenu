//
//  PopoverMenu.swift
//  PopoverMenu
//
//  Created by 玉垒浮云 on 2024/8/9.
//

import UIKit

protocol ReusableView { }

extension ReusableView {
    static var reuseIdentifier: String {
        return String(describing: self)
    }
}

extension UITableViewCell: ReusableView { }

struct PopoverLayout {
    struct ItemSize {
        enum WidthDimension {
            case fixed(CGFloat)
            case flexible(maxWidth: CGFloat)
        }
        
        enum HeightDimension {
            case fixed(CGFloat)
            case adaptive
        }
        
        let widthDimension: WidthDimension
        let heightDimension: HeightDimension
    }
    
    enum PopoverHeight {
        case fixed(CGFloat)
        case adaptive(maxHeight: CGFloat)
    }
    
    let itemSize: ItemSize
    var itemSpacing: CGFloat = 0
    var height: PopoverHeight = .adaptive(maxHeight: .infinity)
    var contentInset: NSDirectionalEdgeInsets = .zero
}

enum PopoverPosition {
    case topLeft, topCenter, topRight
    case bottomLeft, bottomCenter, bottomRight
}

final class PopoverMenu<Cell: UITableViewCell, Item: Equatable>: UIView, UITableViewDataSource, UITableViewDelegate {
    typealias CellConfigurationHandler = (_ cell: Cell, _ index: Int, _ itemIdentifier: Item) -> Void
    
    private let cellConfigurationHandler: CellConfigurationHandler
    
    private let tableView = UITableView()
    
    private var backgroundView: UIView?
    
    private let layout: PopoverLayout
    
    var menuItems: [Item] = [] {
        didSet {
            guard !menuItems.isEmpty, oldValue != menuItems else { return }
            
            updateSelfSize()
            tableView.reloadData()
        }
    }
    
    var bounces: Bool = true
    
    var showsVerticalScrollIndicator: Bool = true
    
    init(layout: PopoverLayout, cellConfigurationHandler: @escaping CellConfigurationHandler) {
        self.layout = layout
        self.cellConfigurationHandler = cellConfigurationHandler
        
        // 使用标准 UITableViewCell 时，不支持设置弹性宽高。
        if Cell.self == UITableViewCell.self {
            if case .flexible = layout.itemSize.widthDimension {
                fatalError("Flexible width is not supported for UITableViewCell. Use a custom cell subclass for flexible width.")
            }
            
            if case .adaptive = layout.itemSize.heightDimension {
                fatalError("Adaptive height is not supported for UITableViewCell. Use a custom cell subclass for adaptive height.")
            }
        }
        super.init(frame: .zero)
        
        setupTableView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func show(from sourceView: UIView, position: PopoverPosition = .bottomLeft, offset: CGPoint = .zero) {
        guard let parentViewController = sourceView.findViewController() else {
            print("Unable to find parent view controller")
            return
        }
        
        parentViewController.view.addSubview(self)
        addBackgroundView()
        
        let sourceFrame = sourceView.convert(sourceView.bounds, to: parentViewController.view)
        frame = calculateTargetFrame(from: sourceFrame, position: position, offset: offset)
    }
    
    @objc func handleBackgroundTap(_ sender: UITapGestureRecognizer) {
        let location = sender.location(in: self)
        if !bounds.contains(location) {
            backgroundView?.removeFromSuperview()
            removeFromSuperview()
        }
    }
    
    // MARK: - UITableViewDataSource
    
    func numberOfSections(in tableView: UITableView) -> Int {
        menuItems.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        1
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Cell.reuseIdentifier) as! Cell
        cellConfigurationHandler(cell, indexPath.section, menuItems[indexPath.section])
        return cell
    }
    
    // MARK: - UITableViewDelegate
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        layout.itemSpacing
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        UIView()
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        print("didSelectRowAt \(indexPath)")
    }
}

private extension PopoverMenu {
    func setupTableView() {
        tableView.bounces = bounces
        tableView.showsVerticalScrollIndicator = showsVerticalScrollIndicator
        tableView.register(Cell.self, forCellReuseIdentifier: Cell.reuseIdentifier)
        tableView.dataSource = self
        tableView.delegate = self
        addSubview(tableView)
        
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: topAnchor, constant: layout.contentInset.top),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -layout.contentInset.bottom),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: layout.contentInset.leading),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -layout.contentInset.trailing)
        ])
    }
    
    func updateSelfSize() {
        var itemWidth: CGFloat = 0, totalHeight: CGFloat = 0
        switch layout.itemSize.widthDimension {
        case .fixed(let width):
            itemWidth = width
        case .flexible(let maxWidth):
            let dummyCell = Cell(style: .default, reuseIdentifier: Cell.reuseIdentifier)
            (0..<menuItems.count).forEach { section in
                cellConfigurationHandler(dummyCell, section, menuItems[section])
                
                let contentSize = dummyCell.contentView.systemLayoutSizeFitting(
                    CGSize(width: maxWidth, height: UIView.layoutFittingCompressedSize.height),
                    withHorizontalFittingPriority: .required,
                    verticalFittingPriority: .fittingSizeLevel
                )
                itemWidth = max(contentSize.width, itemWidth)
                totalHeight += contentSize.height + layout.itemSpacing
            }
        }
        
        if case .fixed(let itemHeight) = layout.itemSize.heightDimension {
            tableView.rowHeight = itemHeight
            totalHeight = (itemHeight + layout.itemSpacing) * CGFloat(menuItems.count)
        }
        
        let width = itemWidth + layout.contentInset.leading + layout.contentInset.trailing
        totalHeight += layout.contentInset.top + layout.contentInset.bottom - layout.itemSpacing
        switch layout.height {
        case .fixed(let height):
            frame.size = CGSize(width: width, height: height)
        case .adaptive(let maxHeight):
            frame.size = CGSize(width: width, height: min(totalHeight, maxHeight))
        }
    }
    
    func addBackgroundView() {
        guard let superview, let window else { return }
        
        let originOfSuperViewInWindow = superview.convert(superview.bounds.origin, to: window)
        if backgroundView == nil {
            backgroundView = UIView()
            backgroundView?.backgroundColor = .black.withAlphaComponent(0.5)
            
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap))
            backgroundView?.addGestureRecognizer(tapGesture)
        }
        backgroundView?.frame = CGRect(x: -originOfSuperViewInWindow.x, y: -originOfSuperViewInWindow.y, width: window.bounds.width, height: window.bounds.height)
        superview.addSubview(backgroundView!)
        superview.insertSubview(backgroundView!, belowSubview: self)
    }
    
    private func calculateTargetFrame(from sourceFrame: CGRect, position: PopoverPosition, offset: CGPoint) -> CGRect {
        var x: CGFloat = 0, y: CGFloat = 0

        switch position {
        case .topLeft, .bottomLeft:
            x = sourceFrame.minX
        case .topCenter, .bottomCenter:
            x = sourceFrame.midX - bounds.width / 2
        case .topRight, .bottomRight:
            x = sourceFrame.maxX - bounds.width
        }

        switch position {
        case .topLeft, .topCenter, .topRight:
            y = sourceFrame.minY - bounds.height
        case .bottomLeft, .bottomCenter, .bottomRight:
            y = sourceFrame.maxY
        }

        return CGRect(x: x + offset.x, y: y + offset.y, width: bounds.width, height: bounds.height)
    }
}

// 辅助方法：查找视图所属的视图控制器
fileprivate extension UIView {
    func findViewController() -> UIViewController? {
        if let nextResponder = self.next as? UIViewController {
            return nextResponder
        } else if let nextResponder = self.next as? UIView {
            return nextResponder.findViewController()
        } else {
            return nil
        }
    }
}
