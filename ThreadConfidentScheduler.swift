//
//  ThreadConfidentScheduler.swift
//  RxThreadConfidentScheduler
//
//  Created by Siarhei Barysenka on 7/5/17.
//  Copyright © 2017 Siarhei Barysenka. All rights reserved.
//

import RxSwift

final class ThreadConfidentScheduler: SchedulerType {
    var now: RxTime {
        return Date()
    }
    
    private let thread: ThreadWithRunLoop
    private let timerQueue: DispatchQueue
    
    init(name: String = "com.threadConfidentScheduler") {
        self.thread = ThreadWithRunLoop(name: name)
        self.timerQueue = DispatchQueue(label: name + ".timerQueue", attributes: [])
    }
    
    func schedule<StateType>(_ state: StateType, action: @escaping (StateType) -> Disposable) -> Disposable {
        let disposable = SingleAssignmentDisposable()
        
        thread.performOperation {
            guard !disposable.isDisposed else {
                return
            }
            
            disposable.setDisposable(action(state))
        }
        
        return disposable
    }
    
    // This implementation is mostly taken from RxSwift.DispatchQueueConfiguration.swift
    func scheduleRelative<StateType>(_ state: StateType, dueTime: RxTimeInterval, action: @escaping (StateType) -> Disposable) -> Disposable {
        let deadline = DispatchTime.now() + DispatchTimeInterval.milliseconds(Int(dueTime * 1_000.0))
        let disposable = CompositeDisposable()
        
        var timer = Optional(DispatchSource.makeTimerSource(queue: timerQueue))
        timer?.scheduleOneshot(deadline: deadline)
        
        let cancelTimer = Disposables.create {
            timer?.cancel()
            timer = nil
        }
        
        timer?.setEventHandler(handler: { [weak self] in
            guard let thread = self?.thread else {
                if !cancelTimer.isDisposed {
                    cancelTimer.dispose()
                }
                
                return
            }
            
            thread.performOperation {
                guard !disposable.isDisposed else {
                    return
                }
                
                _ = disposable.insert(action(state))
                cancelTimer.dispose()
            }
        })
        
        timer?.resume()
        
        _ = disposable.insert(cancelTimer)
        return disposable
    }
}

final class ThreadWithRunLoop {
    final class ThreadTarget: NSObject {
        func run() {
            autoreleasepool {
                RunLoop.current.add(NSMachPort(), forMode: RunLoopMode.defaultRunLoopMode)
                CFRunLoopRun()
            }
        }
        
        func stop() {
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
    }
    
    final class BlockWrapper: NSObject {
        private let block: () -> Void
        
        init(block: @escaping () -> Void) {
            self.block = block
        }
        
        func execute() {
            block()
        }
    }
    
    private let thread: Thread
    private let target = ThreadTarget()
    
    init(name: String) {
        thread = Thread(target: target, selector: #selector(ThreadTarget.run), object: nil)
        thread.name = name
        thread.start()
    }
    
    deinit {
        target.perform(#selector(ThreadTarget.stop), on: thread, with: nil, waitUntilDone: false)
    }
    
    func performOperation(_ operation: @escaping () -> Void) {
        BlockWrapper(block: operation).perform(#selector(BlockWrapper.execute), on: thread, with: nil, waitUntilDone: false)
    }
}
