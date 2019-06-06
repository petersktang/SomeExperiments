//
//  MultiSectionCollectionViewDataSource.swift
//  RxRealmDataSources_Example
//
//  Created by Peter Tang on 30/5/2019.
//  Copyright © 2019 CocoaPods. All rights reserved.
//

import UIKit
import RealmSwift
import RxRealm
import RxSwift

public class MultiSectionCollectionViewDataSource: NSObject {
    fileprivate typealias _CollectionViewCell = (UICollectionView, IndexPath) -> UICollectionViewCell
    fileprivate typealias _SupplementaryConfig = (UICollectionView, String, IndexPath) -> UICollectionReusableView
    fileprivate typealias _ItemCount = () -> Int
    
    private let bag:DisposeBag
    private let _supplementaryConfig : _SupplementaryConfig?

    fileprivate struct Section {
        let sectionID : Int
        let cell: _CollectionViewCell
        let itemCount: _ItemCount
        init(_ sectionID: Int, _ cell: @escaping _CollectionViewCell, _ itemCount: @escaping _ItemCount) {
            self.sectionID = sectionID
            self.cell = cell
            self.itemCount = itemCount
        }
    }
    fileprivate var _sections:[Section?]=[]
    
    init(bag:DisposeBag, _ supplementaryConfig : ((UICollectionView, String, IndexPath) -> UICollectionReusableView)? = nil) {
        self.bag = bag
        self._supplementaryConfig = supplementaryConfig
        super.init()
    }
    
    fileprivate struct RealmChangesetIndexPath {
        fileprivate let deleted: [IndexPath]
        fileprivate let inserted: [IndexPath]
        fileprivate let updated: [IndexPath]
    }
    fileprivate var _realmSections : [Int: Observable<(Int, RealmChangesetIndexPath?)> ] = [:]
    fileprivate var sectionCurrentTotal : [Int: Int ] = [:]

}

extension MultiSectionCollectionViewDataSource {
    public func addSection<Item>(items:[Item],
                                 configure: @escaping (UICollectionView, IndexPath, Item) -> UICollectionViewCell) {
        let _item : (Int) -> Item = { items[$0] }
        let _configureCell : _CollectionViewCell = { cv, ip in
            configure(cv, ip, _item(ip.row) )
        }
        let _count: _ItemCount = { items.count }
        let currentSectionID = _sections.count
        _sections.append(Section(currentSectionID, _configureCell, _count))
    }
    public func addSection<Item>(items realmItems: AnyRealmCollection<Item>,
                                 configure: @escaping (UICollectionView, IndexPath, Item) -> UICollectionViewCell) {
        let _item : (Int) -> Item = { realmItems[$0] }
        let _configureCell : _CollectionViewCell = { cv, ip in
            configure(cv, ip, _item(ip.row) )
        }
        let _count: _ItemCount = { realmItems.count }
        let currentSectionID = _sections.count
        _sections.append(Section(currentSectionID, _configureCell, _count))
    }
    public func addSection<Item>(items observable: Observable<(AnyRealmCollection<Item>, RealmChangeset?)>,
                                 configure: @escaping (UICollectionView, IndexPath, Item) -> UICollectionViewCell) {
        let currentSectionID = _sections.count
        _sections.append(nil)
        
        let _ = observable.first().subscribe(onSuccess: { [weak self] event in
            guard let anyrealmcollection = event?.0 else { fatalError("AnyRealmCollection<Item> cannot populated into \(String(describing: self))") }
            let _item : (Int) -> Item = { anyrealmcollection[$0] }
            let _configureCell : _CollectionViewCell = { cv, ip in
                configure(cv, ip, _item(ip.row))
            }
            let _count = { anyrealmcollection.count }
            let section = Section(currentSectionID, _configureCell, _count)
            
            if self?._sections[currentSectionID] == nil {
                self?._sections[currentSectionID] = section
            } else {
                fatalError("How come the section in \(String(describing: self)) is prepopulated")
            }
        }).disposed(by: bag)
        
        // subscriber in applyChanges to dispose
        let indexPathChanges: Observable<(Int, RealmChangesetIndexPath?)> = observable.map {
            let (_, realmchanges) = $0
            if let realmchanges = realmchanges {
                let deleted = realmchanges.deleted.map{ IndexPath(row: $0, section: currentSectionID) }
                let inserted = realmchanges.inserted.map{ IndexPath(row: $0, section: currentSectionID) }
                let updated = realmchanges.updated.map{ IndexPath(row: $0, section: currentSectionID) }
                let result = RealmChangesetIndexPath(deleted: deleted, inserted: inserted, updated: updated)
                return (currentSectionID, result)
            } else {
                return (currentSectionID, nil)
            }
        }
        _realmSections[currentSectionID] = indexPathChanges
    }
    
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
                guard bufferedArray.count > 0 else {
                    // WHY WHY TELL ME WHY
                    collectionView.reloadData()
                    return
                }
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
                        // hard to mix multiple updates of the same section => not sure how the entry sequence affects the delete and insert indexpath
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

}

extension MultiSectionCollectionViewDataSource: UICollectionViewDataSource {
    
    public func numberOfSections(in collectionView: UICollectionView) -> Int {
        return _sections.count
    }
    
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return sectionCurrentTotal[section] ?? _sections[section]?.itemCount() ?? 0
    }
    
    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        return _sections[indexPath.section]?.cell(collectionView, indexPath) ?? UICollectionViewCell()
    }

    public func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        return self._supplementaryConfig!(collectionView, kind, indexPath)
    }

//    func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool
//    func collectionView(_ collectionView: UICollectionView, moveItemAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath)
//    func collectionView(_ collectionView: UICollectionView, indexPathForIndexTitle title: String, at index: Int) -> IndexPath

}
