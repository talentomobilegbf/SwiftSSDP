//
//  File.swift
//  
//
//  Created by Alexander Heinrich on 16.02.23.
//

import Foundation

class Weak<T: AnyObject> {
  weak var object : T?
  init (_ object: T) {
    self.object = object
  }
}
