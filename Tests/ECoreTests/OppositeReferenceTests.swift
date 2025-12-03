//
// OppositeReferenceTests.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Testing
@testable import ECore
import Foundation

// MARK: - Opposite Reference Tests

@Suite("Opposite Reference Tests")
struct OppositeReferenceTests {
    
    // MARK: - Basic Opposite Reference Tests
    
    @Test func testBidirectionalReferenceCreation() async throws {
        var bookClass = EClass(name: "Book")
        var authorClass = EClass(name: "Author")

        var booksRef = EReference(name: "books", eType: bookClass, upperBound: -1)
        let authorRef = EReference(name: "author", eType: authorClass, opposite: booksRef.id)
        booksRef.opposite = authorRef.id

        authorClass.eStructuralFeatures = [booksRef]
        bookClass.eStructuralFeatures = [authorRef]
        
        #expect(booksRef.opposite == authorRef.id)
        #expect(authorRef.opposite == booksRef.id)
        #expect(booksRef.isMany == true)
        #expect(authorRef.isMany == false)
    }
    
    @Test func testOppositeReferenceResolution() async throws {
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://opposites")

        var bookClass = EClass(name: "Book")
        var authorClass = EClass(name: "Author")

        var booksRef = EReference(name: "books", eType: bookClass, upperBound: -1)
        let authorRef = EReference(name: "author", eType: authorClass, opposite: booksRef.id)
        booksRef.opposite = authorRef.id

        authorClass.eStructuralFeatures = [booksRef]
        bookClass.eStructuralFeatures = [authorRef]
        
        let author = DynamicEObject(eClass: authorClass)
        let book1 = DynamicEObject(eClass: bookClass)
        let book2 = DynamicEObject(eClass: bookClass)
        
        await resource.add(author)
        await resource.add(book1)
        await resource.add(book2)
        
        // Resolve opposite references through ResourceSet
        let resolvedAuthorRef = await resourceSet.resolveOpposite(booksRef)
        let resolvedBooksRef = await resourceSet.resolveOpposite(authorRef)
        
        #expect(resolvedAuthorRef?.id == authorRef.id)
        #expect(resolvedBooksRef?.id == booksRef.id)
    }
    
    // MARK: - One-to-One Opposite Tests
    
    @Test func testOneToOneOppositeReferences() async throws {
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://one-to-one")

        var personClass = EClass(name: "Person")
        var passportClass = EClass(name: "Passport")

        var passportRef = EReference(name: "passport", eType: passportClass)
        let ownerRef = EReference(name: "owner", eType: personClass, opposite: passportRef.id)
        passportRef.opposite = ownerRef.id

        personClass.eStructuralFeatures = [passportRef]
        passportClass.eStructuralFeatures = [ownerRef]

        let person = DynamicEObject(eClass: personClass)
        let passport = DynamicEObject(eClass: passportClass)

        await resource.add(person)
        await resource.add(passport)

        // Set one side using Resource API - should automatically set the other
        await resource.eSet(objectId: person.id, feature: "passport", value: passport.id)

        let personPassport = await resource.eGet(objectId: person.id, feature: "passport") as? EUUID
        let passportOwner = await resource.eGet(objectId: passport.id, feature: "owner") as? EUUID

        #expect(personPassport == passport.id)
        #expect(passportOwner == person.id)
    }
    
    @Test func testOneToOneOppositeUnset() async throws {
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://one-to-one-unset")

        var personClass = EClass(name: "Person")
        var passportClass = EClass(name: "Passport")

        var passportRef = EReference(name: "passport", eType: passportClass)
        let ownerRef = EReference(name: "owner", eType: personClass, opposite: passportRef.id)
        passportRef.opposite = ownerRef.id

        personClass.eStructuralFeatures = [passportRef]
        passportClass.eStructuralFeatures = [ownerRef]

        let person = DynamicEObject(eClass: personClass)
        let passport = DynamicEObject(eClass: passportClass)

        await resource.add(person)
        await resource.add(passport)

        // Set initial relationship using Resource API
        await resource.eSet(objectId: person.id, feature: "passport", value: passport.id)

        var personPassport = await resource.eGet(objectId: person.id, feature: "passport") as? EUUID
        var passportOwner = await resource.eGet(objectId: passport.id, feature: "owner") as? EUUID
        #expect(personPassport == passport.id)
        #expect(passportOwner == person.id)

        // Unset one side using Resource API - should automatically unset the other
        await resource.eSet(objectId: person.id, feature: "passport", value: nil)

        personPassport = await resource.eGet(objectId: person.id, feature: "passport") as? EUUID
        passportOwner = await resource.eGet(objectId: passport.id, feature: "owner") as? EUUID
        #expect(personPassport == nil)
        #expect(passportOwner == nil)
    }
    
    // MARK: - One-to-Many Opposite Tests
    
    @Test func testOneToManyOppositeReferences() async throws {
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://one-to-many")

        var departmentClass = EClass(name: "Department")
        var employeeClass = EClass(name: "Employee")

        var employeesRef = EReference(name: "employees", eType: employeeClass, upperBound: -1, containment: true)
        let departmentRef = EReference(name: "department", eType: departmentClass, opposite: employeesRef.id)
        employeesRef.opposite = departmentRef.id

        departmentClass.eStructuralFeatures = [employeesRef]
        employeeClass.eStructuralFeatures = [departmentRef]
        
        let department = DynamicEObject(eClass: departmentClass)
        let employee1 = DynamicEObject(eClass: employeeClass)
        let employee2 = DynamicEObject(eClass: employeeClass)
        let employee3 = DynamicEObject(eClass: employeeClass)

        await resource.add(department)
        await resource.add(employee1)
        await resource.add(employee2)
        await resource.add(employee3)

        // Set many side using Resource API - should automatically set single sides
        await resource.eSet(objectId: department.id, feature: "employees", value: [employee1.id, employee2.id, employee3.id])

        let employees = await resource.eGet(objectId: department.id, feature: "employees") as? [EUUID]
        let emp1Dept = await resource.eGet(objectId: employee1.id, feature: "department") as? EUUID
        let emp2Dept = await resource.eGet(objectId: employee2.id, feature: "department") as? EUUID
        let emp3Dept = await resource.eGet(objectId: employee3.id, feature: "department") as? EUUID

        #expect(employees?.count == 3)
        #expect(employees?.contains(employee1.id) == true)
        #expect(employees?.contains(employee2.id) == true)
        #expect(employees?.contains(employee3.id) == true)

        #expect(emp1Dept == department.id)
        #expect(emp2Dept == department.id)
        #expect(emp3Dept == department.id)
    }
    
    @Test func testOneToManyOppositeRemoval() async throws {
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://one-to-many-remove")

        var departmentClass = EClass(name: "Department")
        var employeeClass = EClass(name: "Employee")

        var employeesRef = EReference(name: "employees", eType: employeeClass, upperBound: -1, containment: true)
        let departmentRef = EReference(name: "department", eType: departmentClass, opposite: employeesRef.id)
        employeesRef.opposite = departmentRef.id

        departmentClass.eStructuralFeatures = [employeesRef]
        employeeClass.eStructuralFeatures = [departmentRef]

        let department = DynamicEObject(eClass: departmentClass)
        let employee1 = DynamicEObject(eClass: employeeClass)
        let employee2 = DynamicEObject(eClass: employeeClass)

        await resource.add(department)
        await resource.add(employee1)
        await resource.add(employee2)

        // Set initial relationship using Resource API
        await resource.eSet(objectId: department.id, feature: "employees", value: [employee1.id, employee2.id])

        var employees = await resource.eGet(objectId: department.id, feature: "employees") as? [EUUID]
        #expect(employees?.count == 2)

        // Remove one employee using Resource API - should update both sides
        await resource.eSet(objectId: department.id, feature: "employees", value: [employee1.id])

        employees = await resource.eGet(objectId: department.id, feature: "employees") as? [EUUID]
        let emp1Dept = await resource.eGet(objectId: employee1.id, feature: "department") as? EUUID
        let emp2Dept = await resource.eGet(objectId: employee2.id, feature: "department") as? EUUID

        #expect(employees?.count == 1)
        #expect(employees?.contains(employee1.id) == true)
        #expect(employees?.contains(employee2.id) == false)

        #expect(emp1Dept == department.id)
        #expect(emp2Dept == nil)
    }
    
    // MARK: - Many-to-Many Opposite Tests
    
    @Test func testManyToManyOppositeReferences() async throws {
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://many-to-many")

        var studentClass = EClass(name: "Student")
        var courseClass = EClass(name: "Course")

        var coursesRef = EReference(name: "courses", eType: courseClass, upperBound: -1)
        let studentsRef = EReference(name: "students", eType: studentClass, upperBound: -1, opposite: coursesRef.id)
        coursesRef.opposite = studentsRef.id

        studentClass.eStructuralFeatures = [coursesRef]
        courseClass.eStructuralFeatures = [studentsRef]

        var student1 = DynamicEObject(eClass: studentClass)
        var student2 = DynamicEObject(eClass: studentClass)
        let course1 = DynamicEObject(eClass: courseClass)
        let course2 = DynamicEObject(eClass: courseClass)

        await resource.add(student1)
        await resource.add(student2)
        await resource.add(course1)
        await resource.add(course2)

        // Set many-to-many relationships using Resource API
        await resource.eSet(objectId: student1.id, feature: "courses", value: [course1.id, course2.id])
        await resource.eSet(objectId: student2.id, feature: "courses", value: [course1.id])

        let student1Courses = await resource.eGet(objectId: student1.id, feature: "courses") as? [EUUID]
        let student2Courses = await resource.eGet(objectId: student2.id, feature: "courses") as? [EUUID]
        let course1Students = await resource.eGet(objectId: course1.id, feature: "students") as? [EUUID]
        let course2Students = await resource.eGet(objectId: course2.id, feature: "students") as? [EUUID]
        
        #expect(student1Courses?.count == 2)
        #expect(student1Courses?.contains(course1.id) == true)
        #expect(student1Courses?.contains(course2.id) == true)
        
        #expect(student2Courses?.count == 1)
        #expect(student2Courses?.contains(course1.id) == true)
        
        #expect(course1Students?.count == 2)
        #expect(course1Students?.contains(student1.id) == true)
        #expect(course1Students?.contains(student2.id) == true)
        
        #expect(course2Students?.count == 1)
        #expect(course2Students?.contains(student1.id) == true)
    }
    
    @Test func testManyToManyOppositeModification() async throws {
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://many-to-many-mod")

        var authorClass = EClass(name: "Author")
        var bookClass = EClass(name: "Book")

        var booksRef = EReference(name: "books", eType: bookClass, upperBound: -1)
        let authorsRef = EReference(name: "authors", eType: authorClass, upperBound: -1, opposite: booksRef.id)
        booksRef.opposite = authorsRef.id

        authorClass.eStructuralFeatures = [booksRef]
        bookClass.eStructuralFeatures = [authorsRef]

        var author1 = DynamicEObject(eClass: authorClass)
        var author2 = DynamicEObject(eClass: authorClass)
        let book1 = DynamicEObject(eClass: bookClass)
        let book2 = DynamicEObject(eClass: bookClass)

        await resource.add(author1)
        await resource.add(author2)
        await resource.add(book1)
        await resource.add(book2)

        // Set initial relationships using Resource API
        await resource.eSet(objectId: author1.id, feature: "books", value: [book1.id, book2.id])
        await resource.eSet(objectId: author2.id, feature: "books", value: [book1.id])

        // Modify relationship using Resource API - remove author2 from book1
        await resource.eSet(objectId: author2.id, feature: "books", value: [EUUID]())

        let author1Books = await resource.eGet(objectId: author1.id, feature: "books") as? [EUUID]
        let author2Books = await resource.eGet(objectId: author2.id, feature: "books") as? [EUUID]
        let book1Authors = await resource.eGet(objectId: book1.id, feature: "authors") as? [EUUID]
        let book2Authors = await resource.eGet(objectId: book2.id, feature: "authors") as? [EUUID]
        
        #expect(author1Books?.count == 2)
        #expect(author2Books?.isEmpty == true)
        
        #expect(book1Authors?.count == 1)
        #expect(book1Authors?.contains(author1.id) == true)
        #expect(book1Authors?.contains(author2.id) == false)
        
        #expect(book2Authors?.count == 1)
        #expect(book2Authors?.contains(author1.id) == true)
    }
    
    // MARK: - Containment and Opposite Tests
    
    @Test func testContainmentWithOpposite() async throws {
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://containment-opposite")

        var folderClass = EClass(name: "Folder")
        var fileClass = EClass(name: "File")

        var filesRef = EReference(name: "files", eType: fileClass, upperBound: -1, containment: true)
        let parentRef = EReference(name: "parent", eType: folderClass, opposite: filesRef.id)
        filesRef.opposite = parentRef.id

        folderClass.eStructuralFeatures = [filesRef]
        fileClass.eStructuralFeatures = [parentRef]

        let folder = DynamicEObject(eClass: folderClass)
        let file1 = DynamicEObject(eClass: fileClass)
        let file2 = DynamicEObject(eClass: fileClass)

        await resource.add(folder)
        await resource.add(file1)
        await resource.add(file2)

        // Set containment relationship using Resource API
        await resource.eSet(objectId: folder.id, feature: "files", value: [file1.id, file2.id])

        let files = await resource.eGet(objectId: folder.id, feature: "files") as? [EUUID]
        let file1Parent = await resource.eGet(objectId: file1.id, feature: "parent") as? EUUID
        let file2Parent = await resource.eGet(objectId: file2.id, feature: "parent") as? EUUID
        
        #expect(files?.count == 2)
        #expect(files?.contains(file1.id) == true)
        #expect(files?.contains(file2.id) == true)
        
        #expect(file1Parent == folder.id)
        #expect(file2Parent == folder.id)
        
        #expect(filesRef.containment == true)
        #expect(parentRef.containment == false)
        #expect(parentRef.opposite == filesRef.id)  // Container reference
    }
    
    // MARK: - Complex Opposite Scenarios
    
    @Test func testOppositeReferenceChain() async throws {
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://opposite-chain")

        var companyClass = EClass(name: "Company")
        var departmentClass = EClass(name: "Department")
        var employeeClass = EClass(name: "Employee")

        var departmentsRef = EReference(name: "departments", eType: departmentClass, upperBound: -1, containment: true)
        let companyRef = EReference(name: "company", eType: companyClass, opposite: departmentsRef.id)
        var employeesRef = EReference(name: "employees", eType: employeeClass, upperBound: -1, containment: true)
        let deptRef = EReference(name: "department", eType: departmentClass, opposite: employeesRef.id)

        departmentsRef.opposite = companyRef.id
        employeesRef.opposite = deptRef.id

        companyClass.eStructuralFeatures = [departmentsRef]
        departmentClass.eStructuralFeatures = [companyRef, employeesRef]
        employeeClass.eStructuralFeatures = [deptRef]

        var company = DynamicEObject(eClass: companyClass)
        var dept1 = DynamicEObject(eClass: departmentClass)
        var dept2 = DynamicEObject(eClass: departmentClass)
        let emp1 = DynamicEObject(eClass: employeeClass)
        let emp2 = DynamicEObject(eClass: employeeClass)
        let emp3 = DynamicEObject(eClass: employeeClass)

        await resource.add(company)
        await resource.add(dept1)
        await resource.add(dept2)
        await resource.add(emp1)
        await resource.add(emp2)
        await resource.add(emp3)

        // Set up containment hierarchy using Resource API
        await resource.eSet(objectId: company.id, feature: "departments", value: [dept1.id, dept2.id])
        await resource.eSet(objectId: dept1.id, feature: "employees", value: [emp1.id, emp2.id])
        await resource.eSet(objectId: dept2.id, feature: "employees", value: [emp3.id])

        // Verify all opposite relationships
        let departments = await resource.eGet(objectId: company.id, feature: "departments") as? [EUUID]
        let dept1Company = await resource.eGet(objectId: dept1.id, feature: "company") as? EUUID
        let dept2Company = await resource.eGet(objectId: dept2.id, feature: "company") as? EUUID

        let dept1Employees = await resource.eGet(objectId: dept1.id, feature: "employees") as? [EUUID]
        let dept2Employees = await resource.eGet(objectId: dept2.id, feature: "employees") as? [EUUID]
        let emp1Dept = await resource.eGet(objectId: emp1.id, feature: "department") as? EUUID
        let emp2Dept = await resource.eGet(objectId: emp2.id, feature: "department") as? EUUID
        let emp3Dept = await resource.eGet(objectId: emp3.id, feature: "department") as? EUUID
        
        #expect(departments?.count == 2)
        #expect(dept1Company == company.id)
        #expect(dept2Company == company.id)
        
        #expect(dept1Employees?.count == 2)
        #expect(dept2Employees?.count == 1)
        #expect(emp1Dept == dept1.id)
        #expect(emp2Dept == dept1.id)
        #expect(emp3Dept == dept2.id)
    }
    
    @Test func testOppositeReferenceNull() async throws {
        let resourceSet = ResourceSet()
        
        var personClass = EClass(name: "Person")
        var addressClass = EClass(name: "Address")
        
        var addressRef = EReference(name: "address", eType: addressClass)
        let personRef = EReference(name: "person", eType: personClass, opposite: addressRef.id)
        addressRef.opposite = personRef.id
        
        personClass.eStructuralFeatures = [addressRef]
        addressClass.eStructuralFeatures = [personRef]
        
        // Test handling null reference case - no opposite exists
        let tempRef = EReference(name: "temp", eType: personClass)
        let nullOpposite = await resourceSet.resolveOpposite(tempRef)
        #expect(nullOpposite == nil)
    }
    
    @Test func testOppositeReferenceCrossCutting() async throws {
        let resourceSet = ResourceSet()
        let resource1 = await resourceSet.createResource(uri: "test://resource1")
        let resource2 = await resourceSet.createResource(uri: "test://resource2")
        
        var bookClass = EClass(name: "Book")
        var reviewClass = EClass(name: "Review")
        
        var reviewsRef = EReference(name: "reviews", eType: reviewClass, upperBound: -1)
        let bookRef = EReference(name: "book", eType: bookClass, opposite: reviewsRef.id)
        reviewsRef.opposite = bookRef.id
        
        bookClass.eStructuralFeatures = [reviewsRef]
        reviewClass.eStructuralFeatures = [bookRef]
        
        var book = DynamicEObject(eClass: bookClass)
        let review1 = DynamicEObject(eClass: reviewClass)
        let review2 = DynamicEObject(eClass: reviewClass)
        
        await resource1.add(book)
        await resource2.add(review1)
        await resource2.add(review2)
        
        // Set up cross-resource opposite references using Resource API
        await resource1.eSet(objectId: book.id, feature: "reviews", value: [review1.id, review2.id])

        let reviews = await resource1.eGet(objectId: book.id, feature: "reviews") as? [EUUID]
        let review1Book = await resource2.eGet(objectId: review1.id, feature: "book") as? EUUID
        let review2Book = await resource2.eGet(objectId: review2.id, feature: "book") as? EUUID
        
        #expect(reviews?.count == 2)
        #expect(reviews?.contains(review1.id) == true)
        #expect(reviews?.contains(review2.id) == true)
        
        #expect(review1Book == book.id)
        #expect(review2Book == book.id)
    }
    
    // MARK: - Error Cases
    
    @Test func testInvalidOppositeReference() async throws {
        let resourceSet = ResourceSet()
        
        var personClass = EClass(name: "Person")
        var bookClass = EClass(name: "Book")
        
        let booksRef = EReference(name: "books", eType: bookClass, upperBound: -1)
        let invalidRef = EReference(name: "invalid", eType: personClass, opposite: EUUID()) // Invalid opposite ID
        
        personClass.eStructuralFeatures = [booksRef]
        bookClass.eStructuralFeatures = [invalidRef]
        
        // Try to resolve invalid opposite
        let resolved = await resourceSet.resolveOpposite(invalidRef)
        #expect(resolved == nil)
    }
}