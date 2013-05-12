package org.eclipse.xtend.java2xtend

import java.util.List
import org.eclipse.jdt.core.dom.ASTNode
import org.eclipse.jdt.core.dom.ASTVisitor
import org.eclipse.jdt.core.dom.Block
import org.eclipse.jdt.core.dom.BodyDeclaration
import org.eclipse.jdt.core.dom.ChildListPropertyDescriptor
import org.eclipse.jdt.core.dom.EnhancedForStatement
import org.eclipse.jdt.core.dom.Expression
import org.eclipse.jdt.core.dom.FieldAccess
import org.eclipse.jdt.core.dom.FieldDeclaration
import org.eclipse.jdt.core.dom.MethodDeclaration
import org.eclipse.jdt.core.dom.MethodInvocation
import org.eclipse.jdt.core.dom.Modifier
import org.eclipse.jdt.core.dom.NameWrapper
import org.eclipse.jdt.core.dom.PrimitiveType
import org.eclipse.jdt.core.dom.SimpleName
import org.eclipse.jdt.core.dom.TypeDeclaration
import org.eclipse.jdt.core.dom.TypeLiteral
import org.eclipse.jdt.core.dom.VariableDeclarationFragment
import org.eclipse.jdt.core.dom.VariableDeclarationStatement

class ConvertingVisitor extends ASTVisitor {
	override visit(TypeDeclaration node) {
		val modifiers = node.modifiers.map[it as Modifier]
		node.modifiers.removeAll(modifiers.filter[public])
		true
	}

	override visit(FieldDeclaration node) {
		val modifiers = modifiers(node.modifiers)
		val hasInitializer = !node.fragments.filter[it instanceof VariableDeclarationFragment].map[
			it as VariableDeclarationFragment].filter[initializer != null && initializer?.toString.trim != 'null'].empty
		if (hasInitializer) {
			replaceTypeWith(node, if(modifiers.exists[final]) 'var' else 'val');
		}
		removeDefaultModifiers(node)
		false
	}

	override visit(EnhancedForStatement node) {
		val ast = node.AST
		node.parameter.type = ast.newSimpleType(new NameWrapper(ast, ''))
		true
	}

	override visit(VariableDeclarationStatement node) {
		val ast = node.AST
		val modifiers = modifiers(node.modifiers)
		node.modifiers
		val valOrVar = if(modifiers.filter[final].empty) 'var' else 'val'
		val hasInitializer = node.fragments
			.filter[it instanceof VariableDeclarationFragment]
			.map[it as VariableDeclarationFragment]
			.exists[initializer != null && initializer?.toString.trim != 'null']
		node.modifiers.removeAll(modifiers.filter[final])
		if (hasInitializer) {
			node.type = ast.newSimpleType(ast.newName(valOrVar))
		} else {
			node.setType(ast.newSimpleType(new NameWrapper(ast, valOrVar + ' ' + node.type)))
		}
		true
	}

	override visit(Block node) {
		println("------------------------")
		node.accept(new DebugVisitor(""))
		true
	}

	def modifiers(List<?> modifiers) {
		modifiers.filter[it instanceof Modifier].map[it as Modifier]
	}

	def removeDefaultModifiers(BodyDeclaration node) {
		val modifiers = modifiers(node.modifiers)
		node.modifiers.removeAll(modifiers.filter[private || final])
	}
	

	override visit(TypeLiteral qname) {
		val methodCall = qname.AST.newMethodInvocation
		methodCall.name = qname.AST.newSimpleName("typeof")
		methodCall.arguments.add(qname.AST.newSimpleName(qname.type.toString))
		replaceNode(qname, methodCall)
		false
	}
	
	override visit(MethodInvocation node) {
		if (node.expression?.toString == "System.out") {
			if (node.name.toString.startsWith("print")) {
				node.expression.delete
				return true
			}
		}
		val getterPrefixes = #['is','get','has']
		
		if (node.arguments.empty) {
			val name = node.name;
			val identifier = name.identifier
			val matchingPrefix = getterPrefixes.findFirst [
				identifier.startsWith(it)
			]
			if (matchingPrefix != null) {
				val newName = identifier.substring(matchingPrefix.length).toFirstLower
				val newNode = node.AST.newFieldAccess() => [f|					
						f.expression = ASTNode::copySubtree(node.AST, node.expression) as Expression
						f.name = new NameWrapper(node.AST, newName) 
					]
				replaceNode(node, newNode)
			}
			return true
		}
		true
	}
	
	def replaceNode(ASTNode node, Expression exp) {
		val parent = node.parent
		val location = node.locationInParent
		if (location instanceof ChildListPropertyDescriptor && location.id == "arguments") {
			val parentCall = parent as MethodInvocation
			val index = parentCall.arguments.indexOf(node)
			if (index >= 0) {
				parentCall.arguments.set(index, exp)
			} else {
				throw new RuntimeException("Unable to replace " + node + " in " + parent + " for " + exp)
			}
		} else {
			parent.setStructuralProperty(location, exp)
		}
		exp.accept(this)
	}

	override visit(MethodDeclaration node) {
		val modifiers = modifiers(node.modifiers)
		if (node.constructor) {
			node.name = new NameWrapper(node.AST, "new")
		} else {
			val ast = node.AST
			var decl = 'def'
			val retType = node.returnType2
			if (modifiers.exists[abstract] || (retType.primitiveType && (retType as PrimitiveType).getPrimitiveTypeCode.toString == "void")) {
				decl = decl + ' ' + node.returnType2
			}
			node.returnType2 = ast.newSimpleType(new NameWrapper(ast, decl))
		}
		node.modifiers.removeAll(modifiers.filter[public])
		true
	}

	def replaceTypeWith(FieldDeclaration node, String valOrVar) {
		val ast = node.getAST()
		val type = ast.newSimpleType(ast.newName(valOrVar))
		node.setType(type);
	}

	def boolean isAbstract(Iterable<Modifier> modifiers) {
		!modifiers.filter[it.abstract].empty
	}

	def getModifiers(MethodDeclaration node) {
		node.modifiers.map[it as Modifier].filter[!it.public]
	}

}
