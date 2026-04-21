// Derived from OpenScanner (MIT) and StringMetric.swift reference.
// Source repositories:
// - https://github.com/pencilresearch/OpenScanner
// - https://github.com/autozimu/StringMetric.swift
//
// Copyright (c) 2024 Pencil Research
// MIT License - see ThirdPartyNotices.md

import Foundation

extension String {
    var length: Int { count }

    /// Jaro-Winkler similarity score in [0, 1].
    func jaroWinkler(_ target: String) -> Double {
        var stringOne = self
        var stringTwo = target
        if stringOne.count > stringTwo.count {
            stringTwo = self
            stringOne = target
        }

        let stringOneCount = stringOne.count
        let stringTwoCount = stringTwo.count

        if stringOneCount == 0 && stringTwoCount == 0 {
            return 1.0
        }

        let matchingDistance = stringTwoCount / 2
        var matchingCharactersCount: Double = 0
        var transpositionsCount: Double = 0
        var previousPosition = -1

        for (i, stringOneChar) in stringOne.enumerated() {
            for (j, stringTwoChar) in stringTwo.enumerated() {
                if max(0, i - matchingDistance)..<min(stringTwoCount, i + matchingDistance) ~= j {
                    if stringOneChar == stringTwoChar {
                        matchingCharactersCount += 1
                        if previousPosition != -1 && j < previousPosition {
                            transpositionsCount += 1
                        }
                        previousPosition = j
                        break
                    }
                }
            }
        }

        if matchingCharactersCount == 0.0 {
            return 0.0
        }

        let commonPrefixCount = min(max(Double(commonPrefix(with: target).count), 0), 4)
        let jaroSimilarity = (matchingCharactersCount / Double(stringOneCount)
            + matchingCharactersCount / Double(stringTwoCount)
            + (matchingCharactersCount - transpositionsCount) / matchingCharactersCount) / 3

        let commonPrefixScalingFactor = 0.1
        return jaroSimilarity + commonPrefixCount * commonPrefixScalingFactor * (1 - jaroSimilarity)
    }
}
