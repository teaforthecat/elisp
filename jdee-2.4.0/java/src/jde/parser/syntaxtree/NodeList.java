//
// Generated by JTB 1.1.2
//

package jde.parser.syntaxtree;

import java.util.*;

/**
 * Represents a grammar list, e.g. ( A )+
 */
public class NodeList implements NodeListInterface {
   public NodeList() {
      nodes = new Vector();
   }

   public NodeList(Node firstNode) {
      nodes = new Vector();
      addNode(firstNode);
   }

   public void addNode(Node n) {
      nodes.addElement(n);
   }

   public Enumeration elements() { return nodes.elements(); }
   public Node elementAt(int i)  { return (Node)nodes.elementAt(i); }
   public int size()             { return nodes.size(); }
   public void accept(jde.parser.visitor.Visitor v) {
      v.visit(this);
   }

   public Vector nodes;
}
