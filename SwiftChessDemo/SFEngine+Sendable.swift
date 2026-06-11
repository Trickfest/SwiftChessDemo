//
// SwiftChessDemo provides an iOS SwiftUI chess demo built with SwiftChessTools and StockfishEmbedded.
//
// See THIRD_PARTY.md for dependency attribution and license details.
//
// Licensed under the GNU General Public License v3.0.
// You may obtain a copy of the License at: https://www.gnu.org/licenses/gpl-3.0.html
// See the LICENSE file for more information.
//

import Foundation

/// Marks the Objective-C engine wrapper as Sendable for Swift concurrency.
///
/// The engine is internally synchronized; we avoid copying it across tasks,
/// but this conformance allows safe storage in Swift async contexts.
extension SFEngine: @unchecked Sendable {}
