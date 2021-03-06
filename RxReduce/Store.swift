//
//  Store.swift
//  RxReduce
//
//  Created by Thibault Wittemberg on 18-04-15.
//  Copyright (c) RxSwiftCommunity. All rights reserved.
//

import Foundation
import RxSwift
import RxCocoa

/// A Reducer mutates an input state into an output state according to an action
public typealias Reducer<StateType: State> = (_ state: StateType?, _ action: Action) -> StateType

/// A Middleware has not effect on the state, it us just triggered by a dispatch action
public typealias Middleware<StateType: State> = (_ state: StateType?, _ action: Action) -> Void

/// A Store holds the state, mutate the state through actions / reducers and exposes the state via a Driver
/// A Store is dedicated to a State Type
public protocol StoreType {

    /// A store is dedicated to the mutation/observation of this StateType
    associatedtype StateType: State

    /// The current State or SubState (UI compliant)
    ///
    /// - Parameter from: the closure that allows to extract a sub state
    /// - Returns: a Driver of the mutated sub state
    func state<SubStateType> (from: @escaping (StateType) -> SubStateType) -> Driver<SubStateType>

    /// The current State or SubState (UI compliant), avoiding duplicate notifications in case of state equality
    ///
    /// - Parameter from: the closure that allows to extract a sub state
    /// - Returns: a Driver of the mutated sub state
    func state<SubStateType: Equatable> (from: @escaping (StateType) -> SubStateType) -> Driver<SubStateType>

    /// Inits the Store with its reducers stack
    ///
    /// - Parameter reducers: the reducers to be executed by the dispatch function
    /// - Parameter middlewares: the middlewartes to be executed by the dispatch function (the will be executed in reverse order)
    init(withReducers reducers: [Reducer<StateType>], withMiddlewares middlewares: [Middleware<StateType>]?)

    /// Dispatch an action through the reducers to mutate the state
    ///
    /// - Parameter action: the actual action that will go through the reducers
    func dispatch (action: Action)
}

/// A default store that will handle a specific kind of State
public final class Store<StateType: State>: StoreType {

    private let disposeBag = DisposeBag()

    private let stateSubject = BehaviorRelay<StateType?>(value: nil)
    let reducers: [Reducer<StateType>]
    let middlewares: [Middleware<StateType>]?

    // swiftlint:disable force_cast
    public func state<SubStateType>(from: @escaping (StateType) -> SubStateType = { (state: StateType) in return (state as! SubStateType) }) -> Driver<SubStateType> {
        return self.stateSubject
            .asDriver()
            .filter { $0 != nil }
            .map { $0! }
            .map { (state) -> SubStateType in
                return from(state)
        }
    }
    // swiftlint:enable force_cast

    // swiftlint:disable force_cast
    public func state<SubStateType: Equatable>(from: @escaping (StateType) -> SubStateType = { (state: StateType) in return (state as! SubStateType) }) -> Driver<SubStateType> {
        return self.stateSubject
            .asDriver()
            .filter { $0 != nil }
            .map { $0! }
            .map { (state) -> SubStateType in
                return from(state)
            }.distinctUntilChanged()
    }
    // swiftlint:enable force_cast

    public init(withReducers reducers: [Reducer<StateType>], withMiddlewares middlewares: [Middleware<StateType>]? = nil) {
        self.reducers = reducers
        self.middlewares = middlewares
    }

    public func dispatch (action: Action) {
        // every received action is converted to an async action
        action
            .toAsync()
            .do(onNext: { [unowned self] (action) in
                self.middlewares?.forEach({ [unowned self] (middleware) in
                    middleware(self.stateSubject.value, action)
                })
            })
            .map { [unowned self] (action) -> StateType? in
                return self.reducers.reduce(self.stateSubject.value, { (currentState, reducer) -> StateType? in
                    return reducer(currentState, action)
                })
            }.subscribe(onNext: { [unowned self] (newState) in
                self.stateSubject.accept(newState)
            }).disposed(by: self.disposeBag)
    }
}
