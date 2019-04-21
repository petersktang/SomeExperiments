//
//  AttempttUnderstanding.swift
//  AttempReactive
//
//  Created by Peter Tang on 17/4/2019.
//  Copyright © 2019 Peter Tang. All rights reserved.
//

import UIKit
import RealmSwift
import RxSwift
import RxCocoa


extension ViewController {
    func testUnderstanding() {
        let r = try! Realm()
        // RxRealm.Observable.from(Realm) -> Observable<(Realm, Realm.Notification)>
        // the below is of no use to our current situation.
        let s = r.objects(Timer.self).first!.laps
        let o = Observable<(Realm, Realm.Notification)>.from(realm: r)
    }
    func attempt2() {
        // RxRealm to get Observable<Results>
        let realm = try! Realm()
        let laps = Observable.changeset(from: realm.objects(Timer.self).first!.laps)
            .share()
        // Contextual closure type '(Observable<(AnyRealmCollection<Lap>, RealmChangeset?)>) -> _' expects 1 argument, but 3 were used in closure body
        typealias someType = (LapCollectionCell, IndexPath, Lap)
        // 'someType' (aka '(LapCollectionCell, IndexPath, Lap)') is not convertible to 'Observable<(AnyRealmCollection<Lap>, RealmChangeset?)>'
        // laps.bind(to: binder/observer, curriedArgument: Observable<(AnyRealmCollection<Lap>, RealmChangeset?)>() )
    }

    func attempt4(cv:UICollectionView) {
        let realm = try! Realm()
        let laps = realm.objects(Timer.self).first!.laps
        let timers = realm.objects(Timer.self)
        let s1 = RxSectionModel(model: "First Section", items: [1.0, 2.0, 3.0]) { (cv, ip, it) in
            let cell = cv.dequeueReusableCell(withReuseIdentifier: "DoubleCell", for: ip)
            return cell
        }
        let s2 = RxSectionModel(model: "Second Section", items: [1, 2, 3, 4]) {(cv, ip, it) in
            let cell = cv.dequeueReusableCell(withReuseIdentifier: "IntCell", for: ip)
            return cell
            
        }
        let s3 = RxSectionModel(model: "Third Section", items: ["abc","def","ghi"]) {(cv, ip, it) in
            let cell = cv.dequeueReusableCell(withReuseIdentifier: "StringCell", for: ip)
            return cell
        }
        let s4 = RxSectionModel<String>(model: "Fourth Section", items: laps) {(cv, ip, it) in
            let cell = cv.dequeueReusableCell(withReuseIdentifier: "lapsCell", for: ip)
            return cell
        }
        let s5 = RxSectionModel<String>(model: "Fourth Section", items: timers) {(cv, ip, it) in
            let cell = cv.dequeueReusableCell(withReuseIdentifier: "timersCell", for: ip)
            return cell
        }
        let ss = [s1, s2, s3, s4]
        let o = Observable.just(ss)

        let lapChangess = Observable.changeset(from: realm.objects(Timer.self).first!.laps).share()

        //Something of the below type as the cv.rx.items
        lapChangess.bind(to: cv.rx.items(dataSource: SomeRxCollectionDataSource<String>()))
    }
}

public class SomeRxCollectionDataSource<Section>: NSObject, RxCollectionViewDataSourceType & UICollectionViewDataSource {
    public typealias Element = [RxSectionModel<Section>]
    
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return 0
    }
    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        return UICollectionViewCell()
    }
    public func collectionView(_ collectionView: UICollectionView, observedEvent: Event<[RxSectionModel<Section>]>) {
        print("Some Stupid Event hitting my CollcetionView!")
    }
    override init() {
        super.init()
    }
}

extension Reactive where Base : UICollectionView {
    public func items<DataSource: RxCollectionViewDataSourceType & UICollectionViewDataSource, O: ObservableType>
        (dataSource: DataSource)
        -> (_ source: O)
        -> Disposable
        // where DataSource.Element == O.E
    {
            return Disposables.create {
            }
    }
}
