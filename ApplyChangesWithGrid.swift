public func applyChanges(to collectionView:UICollectionView, animated:Bool = false) {
        collectionView.dataSource = self
        
        if !animated {
            collectionView.collectionViewLayout.invalidateLayout()
            collectionView.reloadData()
        }
        
        let maxObservableStreams = _realmSections.count
        let observeableList : Observable<(Int, RealmChangesetIndexPath?)> = Observable.from( _realmSections.map{ $0.value.asObservable()} ).merge()
        _ = observeableList
            .buffer(timeSpan: 0.35, count: maxObservableStreams * 3 , scheduler: MainScheduler.instance)
            .subscribe(onNext: { bufferedArray in
                guard bufferedArray.count > 0 else { return }
                guard animated, bufferedArray.count <= maxObservableStreams, bufferedArray.filter({ $0.1 == nil }).count == 0 else {
                    collectionView.reloadData()
                    return
                }
                let nonNullArray = bufferedArray.filter({ $0.1 != nil }).map{ ($0.0, $0.1! ) }
                
                var localCountBefore : [Int: Int ] = [:]
                self._realmSections.forEach({ (section, _) in
                    localCountBefore[section] = collectionView.numberOfItems(inSection: section)
                })
                var exitClosure : Bool = false
                var latestCount : [Int: Int] = [:]
                nonNullArray.forEach({ (section, changesetIndexPath) in
                    let entry = latestCount[section]
                    if entry != nil {
                        exitClosure = true
                    }
                    let totalItemCount = self._sections[section]?.itemCount()
                    latestCount[section] = totalItemCount
                    if totalItemCount != localCountBefore[section]! + changesetIndexPath.inserted.count - changesetIndexPath.deleted.count {
                        exitClosure = true
                    }
                })
                guard !exitClosure else {
                    //coming in too fast, better consolidate as one single refresh
                    collectionView.reloadData()
                    return
                }
                
                let deleteList = nonNullArray.flatMap{ $0.1.deleted }
                let insertList = nonNullArray.flatMap{ $0.1.inserted }
                let updateList = nonNullArray.flatMap{ $0.1.updated}
                
                collectionView.performUsingPresentationValues {
                    self.sectionCurrentTotal = localCountBefore
                    if deleteList.count > 0 {
                        for (section, changesetIndexPath) in nonNullArray.filter({ $0.1.deleted.count > 0}) {
                            localCountBefore[section] = localCountBefore[section]! - changesetIndexPath.deleted.count
                        }
                        self.sectionCurrentTotal = localCountBefore
                        //model update has to be completed before calling collectionview.deleteItems
                        collectionView.deleteItems(at: deleteList)
                    }
                    if insertList.count > 0 {
                        for (section, changesetIndexPath) in nonNullArray.filter({ $0.1.inserted.count > 0 }) {
                            localCountBefore[section] = localCountBefore[section]! + changesetIndexPath.inserted.count
                        }
                        self.sectionCurrentTotal = localCountBefore
                        //model update has to be completed before calling collectionview.insertItems
                        collectionView.insertItems(at: insertList)
                    }
                    if updateList.count > 0 {
                        collectionView.reloadItems(at: updateList)
                    }
                    self.sectionCurrentTotal = [:]
                }
            }).disposed(by: bag)
    }
    
import UIKit

extension UIEdgeInsets {
    init(all value: CGFloat) {
        self.init(top: value, left: value, bottom: value, right: value)
    }
}

extension CGFloat {
    
    public var evenRounded: CGFloat {
        var newValue = self.rounded(.towardZero)
        if newValue.truncatingRemainder(dividingBy: 2) == 1 {
            newValue -= 1
        }
        return newValue
    }
}

open class Grid {
    
    open var columns: CGFloat
    open var margin: UIEdgeInsets
    open var padding: UIEdgeInsets
    
    public var verticalMargin: CGFloat {
        return self.margin.top + self.margin.bottom
    }
    
    public var horizontalMargin: CGFloat {
        return self.margin.left + self.margin.right
    }
    
    // line spacing
    public var verticalPadding: CGFloat {
        return self.padding.top + self.padding.bottom
    }
    
    // inter item spacing
    public var horizontalPadding: CGFloat {
        return self.padding.left + self.padding.right
    }
    
    public init(columns: CGFloat = 1, margin: UIEdgeInsets = .zero, padding: UIEdgeInsets = .zero) {
        self.columns = columns
        self.margin = margin
        self.padding = padding
    }
    
    open func size(for view: UIView, ratio: CGFloat, items: CGFloat = 1, gaps: CGFloat? = nil) -> CGSize {
        let size = self.width(for: view, items: items, gaps: gaps)
        return CGSize(width: size, height: (size * ratio).evenRounded)
    }
    
    open func size(for view: UIView, height: CGFloat, items: CGFloat = 1, gaps: CGFloat? = nil) -> CGSize {
        let size = self.width(for: view, items: items, gaps: gaps)
        
        var height = height
        if height < 0 {
            height = view.bounds.size.height - height
        }
        return CGSize(width: size, height: height.evenRounded)
    }
    
    open func width(for view: UIView, items: CGFloat = 1, gaps: CGFloat? = nil) -> CGFloat {
        let gaps = gaps ?? items - 1
        
        let width = view.bounds.size.width - self.horizontalMargin - self.horizontalPadding * gaps
        
        return (width / self.columns * items).evenRounded
    }
    
    open func height(for view: UIView, items: CGFloat = 1, gaps: CGFloat? = nil) -> CGFloat {
        let gaps = gaps ?? items - 1
        
        let height = view.bounds.size.height - self.verticalMargin - self.verticalPadding * gaps
        
        return (height / self.columns * items).evenRounded
    }
}
